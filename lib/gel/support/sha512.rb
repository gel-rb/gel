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
  K0 = K.map { |k| k & 0xffffffff }
  K1 = K.map { |k| k >> 32 }
  #H = [
  #  0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
  #  0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
  #]
  BLOCK_SIZE = 128

  attr_reader :h
  protected :h

  def initialize(m = nil)
    @buffer = ''.b
    @counter = 0

    @a0 = 0xf3bcc908
    @b0 = 0x84caa73b
    @c0 = 0xfe94f82b
    @d0 = 0x5f1d36f1
    @e0 = 0xade682d1
    @f0 = 0x2b3e6c1f
    @g0 = 0xfb41bd6b
    @h0 = 0x137e2179

    @a1 = 0x6a09e667
    @b1 = 0xbb67ae85
    @c1 = 0x3c6ef372
    @d1 = 0xa54ff53a
    @e1 = 0x510e527f
    @f1 = 0x9b05688c
    @g1 = 0x1f83d9ab
    @h1 = 0x5be0cd19

    @w0 = Array.new(80, 0)
    @w1 = Array.new(80, 0)

    if m
      update(m)
    end
  end

  def update(m)
    bytes = m.b

    @buffer << bytes
    @counter += bytes.size

    offset = 0
    while (@buffer.size - offset) >= BLOCK_SIZE
      process(@buffer, offset)
      offset += BLOCK_SIZE
    end

    if offset == @buffer.size
      @buffer.clear
    else
      @buffer.slice!(0, offset)
    end
  end

  REST_RANGE = 16..79
  FULL_RANGE = 0..79

  def process(chunk, offset)
    w0 = @w0
    w1 = @w1

    i = offset
    j = 0
    while j < 16
      w1[j] = chunk.getbyte(i) << 24 | chunk.getbyte(i + 1) << 16 | chunk.getbyte(i + 2) << 8 | chunk.getbyte(i + 3)
      w0[j] = chunk.getbyte(i + 4) << 24 | chunk.getbyte(i + 5) << 16 | chunk.getbyte(i + 6) << 8 | chunk.getbyte(i + 7)
      i += 8
      j += 1
    end

    i = 16
    while i < 80
      w0_15 = w0[i - 15]
      w1_15 = w1[i - 15]
      w0_2 = w0[i - 2]
      w1_2 = w1[i - 2]

      sx0 = ((w0_15 >> 1) | ((w1_15 & 0x1) << 31)) ^
              ((w0_15 >> 8) | ((w1_15 & 0xff) << 24)) ^
              ((w0_15 >> 7 | ((w1_15 & 0x7f) << 25)))
      sx1 = ((w1_15 >> 1) | ((w0_15 & 0x1) << 31)) ^
              ((w1_15 >> 8) | ((w0_15 & 0xff) << 24)) ^
              (w1_15 >> 7)

      sy0 = ((w0_2 >> 19) | ((w1_2 & 0x7ffff) << 13)) ^
              ((w1_2 >> 29) | ((w0_2 & 0x1fffffff) << 3)) ^
              ((w0_2 >> 6) | ((w1_2 & 0x3f) << 26))
      sy1 = ((w1_2 >> 19) | ((w0_2 & 0x7ffff) << 13)) ^
              ((w0_2 >> 29) | ((w1_2 & 0x1fffffff) << 3)) ^
              (w1_2 >> 6)

      n = (w0[i - 16] + sx0 + w0[i - 7] + sy0)
      w1[i] = (w1[i - 16] + sx1 + w1[i - 7] + sy1 + (n >> 32)) & 0xffffffff
      w0[i] = n & 0xffffffff

      i += 1
    end

    a0 = @a0
    a1 = @a1
    b0 = @b0
    b1 = @b1
    c0 = @c0
    c1 = @c1
    d0 = @d0
    d1 = @d1
    e0 = @e0
    e1 = @e1
    f0 = @f0
    f1 = @f1
    g0 = @g0
    g1 = @g1
    h0 = @h0
    h1 = @h1

    i = 0
    while i < 80
      sx0 = ((a0 >> 28) | ((a1 & 0xfffffff) << 4)) ^
              ((a1 >> 2) | ((a0 & 0x3) << 30)) ^
              ((a1 >> 7) | ((a0 & 0x7f) << 25))
      sx1 = ((a1 >> 28) | ((a0 & 0xfffffff) << 4)) ^
              ((a0 >> 2) | ((a1 & 0x3) << 30)) ^
              ((a0 >> 7) | ((a1 & 0x7f) << 25))

      maj0 = (a0 & b0) ^ (a0 & c0) ^ (b0 & c0)
      maj1 = (a1 & b1) ^ (a1 & c1) ^ (b1 & c1)

      ty0 = sx0 + maj0
      ty1 = (sx1 + maj1 + (ty0 >> 32)) & 0xffffffff
      ty0 &= 0xffffffff


      sy0 = ((e0 >> 14) | ((e1 & 0x3fff) << 18)) ^
              ((e0 >> 18) | ((e1 & 0x3ffff) << 14)) ^
              ((e1 >> 9) | ((e0 & 0x1ff) << 23))
      sy1 = ((e1 >> 14) | ((e0 & 0x3fff) << 18)) ^
              ((e1 >> 18) | ((e0 & 0x3ffff) << 14)) ^
              ((e0 >> 9) | ((e1 & 0x1ff) << 23))

      ch0 = (e0 & f0) ^ ((~e0) & g0)
      ch1 = (e1 & f1) ^ ((~e1) & g1)

      tx0 = h0 + sy0 + ch0 + K0[i] + w0[i]
      tx1 = (h1 + sy1 + ch1 + K1[i] + w1[i] + (tx0 >> 32)) & 0xffffffff
      tx0 &= 0xffffffff

      h0 = g0
      h1 = g1
      g0 = f0
      g1 = f1
      f0 = e0
      f1 = e1
      e0 = d0 + tx0
      e1 = (d1 + tx1 + (e0 >> 32)) & 0xffffffff
      e0 &= 0xffffffff
      d0 = c0
      d1 = c1
      c0 = b0
      c1 = b1
      b0 = a0
      b1 = a1
      a0 = tx0 + ty0
      a1 = (tx1 + ty1 + (a0 >> 32)) & 0xffffffff
      a0 &= 0xffffffff

      i += 1
    end

    @a0 += a0
    @a1 = (@a1 + a1 + (@a0 >> 32)) & 0xffffffff
    @a0 &= 0xffffffff
    @b0 += b0
    @b1 = (@b1 + b1 + (@b0 >> 32)) & 0xffffffff
    @b0 &= 0xffffffff
    @c0 += c0
    @c1 = (@c1 + c1 + (@c0 >> 32)) & 0xffffffff
    @c0 &= 0xffffffff
    @d0 += d0
    @d1 = (@d1 + d1 + (@d0 >> 32)) & 0xffffffff
    @d0 &= 0xffffffff
    @e0 += e0
    @e1 = (@e1 + e1 + (@e0 >> 32)) & 0xffffffff
    @e0 &= 0xffffffff
    @f0 += f0
    @f1 = (@f1 + f1 + (@f0 >> 32)) & 0xffffffff
    @f0 &= 0xffffffff
    @g0 += g0
    @g1 = (@g1 + g1 + (@g0 >> 32)) & 0xffffffff
    @g0 &= 0xffffffff
    @h0 += h0
    @h1 = (@h1 + h1 + (@h0 >> 32)) & 0xffffffff
    @h0 &= 0xffffffff
  end

  def raw
    [@a1, @a0, @b1, @b0, @c1, @c0, @d1, @d0, @e1, @e0, @f1, @f0, @g1, @g0, @h1, @h0].pack('N*')
  end

  def digest
    mdi = @counter & 0x7F
    length = [@counter << 3].pack('Q>')

    padlen = mdi < 112 ? 111 - mdi : 239 - mdi

    r = dup
    r.update("\x80".b + "\x00".b * (padlen + 8) + length)
    r.raw
  end

  def hexdigest
    digest.unpack('H*').first
  end
end
