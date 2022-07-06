# frozen_string_literal: true

# MIT License
#
# Copyright (c) 2017 Thomas Dixon
# Copyright (c) 2022 Matthew Draper
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Translated from pysha2
# https://github.com/thomdixon/pysha2/blob/master/sha2/sha512.py

class Gel::Support::SHA512
  def self.hexdigest(s)
    new(s).hexdigest
  end

  K = [
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
    0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
    0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
    0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
    0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
    0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
    0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
    0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
    0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
    0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
    0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
    0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
    0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
    0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
    0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
  ]
  H = [
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
  ]
  BLOCK_SIZE = 128

  attr_reader :h
  protected :h

  def initialize(m = nil)
    @buffer = ''.b
    @counter = 0

    @h = H.dup

    if m
      update(m)
    end
  end

  def rotr(x, y)
    ((x >> y) | (x << (64 - y))) & 0xFFFFFFFFFFFFFFFF
  end

  def update(m)
    bytes = m.b

    @buffer << bytes
    @counter += bytes.size

    while @buffer.size >= BLOCK_SIZE
      process(@buffer.slice!(0, BLOCK_SIZE))
    end
  end

  def process(chunk)
    w = Array.new(80, 0)
    chunk.unpack('Q>*').each_with_index do |x, i|
      w[i] = x
    end

    (16..79).each do |i|
      s0 = rotr(w[i - 15], 1) ^ rotr(w[i - 15], 8) ^ (w[i - 15] >> 7)
      s1 = rotr(w[i - 2], 19) ^ rotr(w[i - 2], 61) ^ (w[i - 2] >> 6)

      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFFFFFFFFFF
    end

    a, b, c, d, e, f, g, h = @h

    (0..79).each do |i|
      s0 = rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39)
      maj = (a & b) ^ (a & c) ^ (b & c)
      t2 = (s0 + maj) & 0xFFFFFFFFFFFFFFFF

      s1 = rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41)
      ch = (e & f) ^ ((~e) & g)
      t1 = (h + s1 + ch + K[i] + w[i]) & 0xFFFFFFFFFFFFFFFF

      h = g
      g = f
      f = e
      e = (d + t1) & 0xFFFFFFFFFFFFFFFF
      d = c
      c = b
      b = a
      a = (t1 + t2) & 0xFFFFFFFFFFFFFFFF
    end

    @h = @h.zip([a, b, c, d, e, f, g, h]).map { |x, y| (x + y) & 0xFFFFFFFFFFFFFFFF }
  end

  def digest
    mdi = @counter & 0x7F
    length = [@counter << 3].pack('Q>')

    padlen = mdi < 112 ? 111 - mdi : 239 - mdi

    r = dup
    r.update("\x80".b + "\x00".b * (padlen + 8) + length)
    r.h.pack('Q>*')
  end

  def hexdigest
    digest.unpack('H*').first
  end
end
