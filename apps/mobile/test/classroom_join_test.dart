import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/classroom_join.dart';

void main() {
  final Uri officialJoinBase = Uri.parse('https://join.minapp.example');

  test('normalizes typed classroom code', () {
    expect(
      normalizeClassroomJoinInput('  tzznpvxbeqc3  '),
      'TZZN-PVXB-EQC3',
    );
  });

  test('accepts only the configured official join origin', () {
    expect(
      normalizeClassroomJoinInput(
        'https://join.minapp.example/c/tzzn-pvxb-eqc3',
        officialJoinBaseUri: officialJoinBase,
      ),
      'TZZN-PVXB-EQC3',
    );
  });

  test('rejects arbitrary HTTPS URL instead of treating it as tenant input', () {
    expect(
      () => normalizeClassroomJoinInput(
        'https://evil.example/c/TZZN-PVXB-EQC3',
        officialJoinBaseUri: officialJoinBase,
      ),
      throwsA(isA<InvalidClassroomJoinInput>()),
    );
  });

  test('rejects query fragment and extra join-link paths', () {
    for (final String input in <String>[
      'https://join.minapp.example/c/TZZN-PVXB-EQC3?next=evil',
      'https://join.minapp.example/c/TZZN-PVXB-EQC3#fragment',
      'https://join.minapp.example/c/TZZN-PVXB-EQC3/extra',
    ]) {
      expect(
        () => normalizeClassroomJoinInput(
          input,
          officialJoinBaseUri: officialJoinBase,
        ),
        throwsA(isA<InvalidClassroomJoinInput>()),
      );
    }
  });

  test('rejects join URLs when no official origin is configured', () {
    expect(
      () => normalizeClassroomJoinInput(
        'https://join.minapp.example/c/TZZN-PVXB-EQC3',
      ),
      throwsA(isA<InvalidClassroomJoinInput>()),
    );
  });

  test('rejects malformed and ambiguous classroom codes', () {
    for (final String input in <String>[
      'TZZN-PVXB-EQC',
      'TZZN-PVXB-EQC0',
      'TZZN-PVXB-EQCI',
    ]) {
      expect(
        () => normalizeClassroomJoinInput(input),
        throwsA(isA<InvalidClassroomJoinInput>()),
      );
    }
  });
}
