from pathlib import Path

path = Path('apps/mobile/lib/girls_app.dart')
text = path.read_text(encoding='utf-8')

replacements = [
    (
        """          colors: <Color>[
            Color(0xFFFFEDF5),
            Color(0xFFF6F0FF),
            _cream,
          ],""",
        """          colors: <Color>[
            Color(0xFFFFEDF5),
            Color(0xFFFFF4E6),
            Color(0xFFFFF8EE),
          ],""",
    ),
    (
        """    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: SizedBox(""",
        """    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: SizedBox(""",
    ),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f'Expected exactly one match for patch block, found {count}. '
            'Refusing to modify girls_app.dart.'
        )
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8', newline='\n')
