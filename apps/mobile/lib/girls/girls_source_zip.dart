import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int maxGirlsSourceEditorZipBytes = 2 * 1024 * 1024;
const int maxGirlsSourceEditorExpandedBytes = 8 * 1024 * 1024;
const int maxGirlsSourceEditorFiles = 100;

const Set<String> _textSuffixes = <String>{
  '.html',
  '.css',
  '.js',
  '.mjs',
  '.json',
  '.txt',
};

const Set<String> _allowedSuffixes = <String>{
  '.html',
  '.css',
  '.js',
  '.mjs',
  '.json',
  '.txt',
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.ico',
  '.mp3',
  '.m4a',
  '.ogg',
  '.wav',
};

String _suffixOf(String path) {
  final int slash = path.lastIndexOf('/');
  final int dot = path.lastIndexOf('.');
  return dot > slash ? path.substring(dot).toLowerCase() : '';
}

String _validatePath(String path) {
  if (path.isEmpty || path.trim() != path) {
    throw const FormatException('ZIP内のファイル名が不正です。');
  }
  if (path.contains('\\') || path.startsWith('/') || path.contains('\u0000')) {
    throw FormatException('ZIP内のファイル名が不正です: $path');
  }
  final List<String> parts = path.split('/');
  if (parts.any((String part) => part.isEmpty || part == '.' || part == '..')) {
    throw FormatException('ZIP内のファイル名が不正です: $path');
  }
  if (!_allowedSuffixes.contains(_suffixOf(path))) {
    throw FormatException('この種類のファイルは編集対象ZIPに含められません: $path');
  }
  return path;
}

int _crc32(List<int> bytes) {
  int crc = 0xffffffff;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; bit += 1) {
      final int mask = -(crc & 1);
      crc = (crc >>> 1) ^ (0xedb88320 & mask);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

class GirlsSourceArchive {
  GirlsSourceArchive._(Map<String, Uint8List> entries)
    : _entries = Map<String, Uint8List>.fromEntries(
        entries.entries.map(
          (MapEntry<String, Uint8List> entry) => MapEntry<String, Uint8List>(
            entry.key,
            Uint8List.fromList(entry.value),
          ),
        ),
      );

  factory GirlsSourceArchive.fromEntries(Map<String, Uint8List> entries) {
    if (entries.isEmpty) {
      throw const FormatException('ZIPに入れるファイルがありません。');
    }
    if (entries.length > maxGirlsSourceEditorFiles) {
      throw const FormatException('ファイル数は100個以下にしてください。');
    }
    int expandedBytes = 0;
    final Map<String, Uint8List> checked = <String, Uint8List>{};
    for (final MapEntry<String, Uint8List> entry in entries.entries) {
      final String path = _validatePath(entry.key);
      expandedBytes += entry.value.length;
      if (expandedBytes > maxGirlsSourceEditorExpandedBytes) {
        throw const FormatException('ファイルの合計サイズは8MB以下にしてください。');
      }
      if (checked.containsKey(path)) {
        throw FormatException('ZIP内に同名ファイルがあります: $path');
      }
      checked[path] = Uint8List.fromList(entry.value);
    }
    if (!checked.containsKey('index.html')) {
      throw const FormatException('ZIP直下に index.html が必要です。');
    }
    return GirlsSourceArchive._(checked);
  }

  factory GirlsSourceArchive.decode(Uint8List zipBytes) {
    if (zipBytes.length < 22 || zipBytes.length > maxGirlsSourceEditorZipBytes) {
      throw const FormatException('正しいサイズのZIPファイルではありません。');
    }
    final ByteData view = ByteData.sublistView(zipBytes);
    int uint16(int offset) => view.getUint16(offset, Endian.little);
    int uint32(int offset) => view.getUint32(offset, Endian.little);

    final int minimumEocd = zipBytes.length - 22 - 0xffff < 0
        ? 0
        : zipBytes.length - 22 - 0xffff;
    int eocd = -1;
    for (int offset = zipBytes.length - 22; offset >= minimumEocd; offset -= 1) {
      if (uint32(offset) == 0x06054b50) {
        eocd = offset;
        break;
      }
    }
    if (eocd < 0) {
      throw const FormatException('ZIPの終端情報が見つかりません。');
    }

    final int diskNumber = uint16(eocd + 4);
    final int centralDisk = uint16(eocd + 6);
    final int entriesOnDisk = uint16(eocd + 8);
    final int entryCount = uint16(eocd + 10);
    final int centralSize = uint32(eocd + 12);
    final int centralOffset = uint32(eocd + 16);
    final int commentLength = uint16(eocd + 20);
    if (diskNumber != 0 || centralDisk != 0 || entriesOnDisk != entryCount) {
      throw const FormatException('分割ZIPには対応していません。');
    }
    if (entryCount > maxGirlsSourceEditorFiles) {
      throw const FormatException('ファイル数は100個以下にしてください。');
    }
    if (eocd + 22 + commentLength != zipBytes.length) {
      throw const FormatException('ZIP終端の長さが不正です。');
    }
    if (centralOffset + centralSize > eocd) {
      throw const FormatException('ZIP中央ディレクトリの位置が不正です。');
    }

    final Map<String, Uint8List> entries = <String, Uint8List>{};
    int expandedBytes = 0;
    int offset = centralOffset;
    for (int index = 0; index < entryCount; index += 1) {
      if (offset + 46 > zipBytes.length || uint32(offset) != 0x02014b50) {
        throw const FormatException('ZIP中央ディレクトリが壊れています。');
      }
      final int flags = uint16(offset + 8);
      final int method = uint16(offset + 10);
      final int expectedCrc = uint32(offset + 16);
      final int compressedSize = uint32(offset + 20);
      final int uncompressedSize = uint32(offset + 24);
      final int nameLength = uint16(offset + 28);
      final int extraLength = uint16(offset + 30);
      final int entryCommentLength = uint16(offset + 32);
      final int localOffset = uint32(offset + 42);
      if ((flags & 0x1) != 0) {
        throw const FormatException('暗号化ZIPは編集できません。');
      }

      final int nameStart = offset + 46;
      final int nameEnd = nameStart + nameLength;
      if (nameEnd + extraLength + entryCommentLength > zipBytes.length) {
        throw const FormatException('ZIP内のファイル名情報が壊れています。');
      }
      late final String rawPath;
      try {
        rawPath = utf8.decode(
          zipBytes.sublist(nameStart, nameEnd),
          allowMalformed: false,
        );
      } on FormatException catch (error) {
        throw FormatException(
          'ZIP内のファイル名はUTF-8である必要があります: ${error.message}',
        );
      }
      offset = nameEnd + extraLength + entryCommentLength;
      if (rawPath.endsWith('/')) {
        continue;
      }
      final String path = _validatePath(rawPath);
      if (entries.containsKey(path)) {
        throw FormatException('ZIP内に同名ファイルがあります: $path');
      }

      if (localOffset + 30 > zipBytes.length || uint32(localOffset) != 0x04034b50) {
        throw FormatException('ZIP内のローカルヘッダーが壊れています: $path');
      }
      final int localMethod = uint16(localOffset + 8);
      final int localNameLength = uint16(localOffset + 26);
      final int localExtraLength = uint16(localOffset + 28);
      if (localMethod != method) {
        throw FormatException('ZIPの圧縮方式情報が一致しません: $path');
      }
      final int dataStart = localOffset + 30 + localNameLength + localExtraLength;
      final int dataEnd = dataStart + compressedSize;
      if (dataEnd > zipBytes.length) {
        throw FormatException('ZIP内のデータが途切れています: $path');
      }
      final Uint8List compressed = Uint8List.fromList(
        zipBytes.sublist(dataStart, dataEnd),
      );
      late final Uint8List data;
      if (method == 0) {
        data = compressed;
      } else if (method == 8) {
        try {
          data = Uint8List.fromList(
            ZLibDecoder(raw: true).convert(compressed),
          );
        } on Object catch (error) {
          throw FormatException('ZIPを展開できません: $path ($error)');
        }
      } else {
        throw FormatException('未対応のZIP圧縮方式です: $path (method=$method)');
      }
      if (data.length != uncompressedSize) {
        throw FormatException('ZIP展開後サイズが一致しません: $path');
      }
      if (_crc32(data) != expectedCrc) {
        throw FormatException('ZIP内のファイルが破損しています: $path');
      }
      expandedBytes += data.length;
      if (expandedBytes > maxGirlsSourceEditorExpandedBytes) {
        throw const FormatException('ファイルの合計サイズは8MB以下にしてください。');
      }
      entries[path] = data;
    }
    if (offset != centralOffset + centralSize) {
      throw const FormatException('ZIP中央ディレクトリの長さが一致しません。');
    }
    if (!entries.containsKey('index.html')) {
      throw const FormatException('ZIP直下に index.html が必要です。');
    }
    return GirlsSourceArchive._(entries);
  }

  final Map<String, Uint8List> _entries;

  List<String> get paths {
    final List<String> values = _entries.keys.toList(growable: false)..sort();
    return values;
  }

  List<String> get textPaths => paths
      .where((String path) => _textSuffixes.contains(_suffixOf(path)))
      .toList(growable: false);

  bool isTextFile(String path) => _textSuffixes.contains(_suffixOf(path));

  String readText(String path) {
    final Uint8List? bytes = _entries[path];
    if (bytes == null) {
      throw ArgumentError.value(path, 'path', 'file does not exist');
    }
    if (!isTextFile(path)) {
      throw ArgumentError.value(path, 'path', 'file is not editable text');
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw FormatException('$path はUTF-8テキストではありません: ${error.message}');
    }
  }

  void writeText(String path, String value) {
    if (!_entries.containsKey(path)) {
      throw ArgumentError.value(path, 'path', 'file does not exist');
    }
    if (!isTextFile(path)) {
      throw ArgumentError.value(path, 'path', 'file is not editable text');
    }
    _entries[path] = Uint8List.fromList(utf8.encode(value));
  }

  Uint8List encode() {
    final List<_ZipRecord> records = <_ZipRecord>[];
    int expandedBytes = 0;
    int localLength = 0;
    for (final String path in paths) {
      _validatePath(path);
      final Uint8List bytes = _entries[path]!;
      expandedBytes += bytes.length;
      if (expandedBytes > maxGirlsSourceEditorExpandedBytes) {
        throw const FormatException('ファイルの合計サイズは8MB以下にしてください。');
      }
      final Uint8List name = Uint8List.fromList(utf8.encode(path));
      records.add(
        _ZipRecord(
          name: name,
          bytes: bytes,
          crc: _crc32(bytes),
          localOffset: localLength,
        ),
      );
      localLength += 30 + name.length + bytes.length;
    }
    if (records.isEmpty || records.length > maxGirlsSourceEditorFiles) {
      throw const FormatException('ZIPのファイル数が不正です。');
    }

    int centralLength = 0;
    for (final _ZipRecord record in records) {
      centralLength += 46 + record.name.length;
    }
    final int totalLength = localLength + centralLength + 22;
    if (totalLength > maxGirlsSourceEditorZipBytes) {
      throw const FormatException('編集後のZIPが2MBを超えます。素材を小さくしてから保存してください。');
    }

    final Uint8List output = Uint8List(totalLength);
    final ByteData view = ByteData.sublistView(output);
    int offset = 0;
    void uint16(int value) {
      view.setUint16(offset, value, Endian.little);
      offset += 2;
    }
    void uint32(int value) {
      view.setUint32(offset, value & 0xffffffff, Endian.little);
      offset += 4;
    }
    void bytes(Uint8List value) {
      output.setRange(offset, offset + value.length, value);
      offset += value.length;
    }

    for (final _ZipRecord record in records) {
      uint32(0x04034b50);
      uint16(20);
      uint16(0x0800);
      uint16(0);
      uint16(0);
      uint16(0x0021);
      uint32(record.crc);
      uint32(record.bytes.length);
      uint32(record.bytes.length);
      uint16(record.name.length);
      uint16(0);
      bytes(record.name);
      bytes(record.bytes);
    }
    final int centralOffset = offset;
    for (final _ZipRecord record in records) {
      uint32(0x02014b50);
      uint16(20);
      uint16(20);
      uint16(0x0800);
      uint16(0);
      uint16(0);
      uint16(0x0021);
      uint32(record.crc);
      uint32(record.bytes.length);
      uint32(record.bytes.length);
      uint16(record.name.length);
      uint16(0);
      uint16(0);
      uint16(0);
      uint16(0);
      uint32(0);
      uint32(record.localOffset);
      bytes(record.name);
    }
    final int centralSize = offset - centralOffset;
    uint32(0x06054b50);
    uint16(0);
    uint16(0);
    uint16(records.length);
    uint16(records.length);
    uint32(centralSize);
    uint32(centralOffset);
    uint16(0);
    if (offset != output.length) {
      throw StateError('ZIP構築サイズが一致しません。');
    }
    return output;
  }
}

class _ZipRecord {
  const _ZipRecord({
    required this.name,
    required this.bytes,
    required this.crc,
    required this.localOffset,
  });

  final Uint8List name;
  final Uint8List bytes;
  final int crc;
  final int localOffset;
}
