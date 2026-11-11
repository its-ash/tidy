/// Number of differing bits between two 64-bit difference hashes (Hamming distance).
int hamming(int a, int b) {
  var x = a ^ b;
  x = x - ((x >>> 1) & 0x5555555555555555);
  x = (x & 0x3333333333333333) + ((x >>> 2) & 0x3333333333333333);
  x = (x + (x >>> 4)) & 0x0f0f0f0f0f0f0f0f;
  return ((x * 0x0101010101010101) >>> 56) & 0xff;
}
