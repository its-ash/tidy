import 'package:flutter_test/flutter_test.dart';
import 'package:tidy/media/hashing.dart';

void main() {
  group('hamming', () {
    test('identical hashes are 0 apart', () {
      expect(hamming(0x1234ABCD5678EF01, 0x1234ABCD5678EF01), 0);
    });

    test('counts single and multiple bit flips', () {
      expect(hamming(0, 1), 1);
      expect(hamming(0, 0xFF), 8);
      expect(hamming(0x0F0F, 0x0F00), 4);
    });

    test('handles the sign bit (64-bit hashes are signed in Dart)', () {
      expect(hamming(0, -1), 64);
      expect(hamming(-1, -1), 0);
      expect(hamming(0, -0x8000000000000000), 1);
      expect(hamming(-0x8000000000000000, 0x7FFFFFFFFFFFFFFF), 64);
    });

    test('is symmetric', () {
      const a = 0x00FF00FF00FF00FF;
      const b = 0x0F0F0F0F0F0F0F0F;
      expect(hamming(a, b), hamming(b, a));
      expect(hamming(a, b), 32);
    });
  });
}
