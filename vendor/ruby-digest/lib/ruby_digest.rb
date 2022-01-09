#--
# Ruby Digest
# =============================================================================
# [![Status](https://travis-ci.org/Solistra/ruby-digest.svg?branch=master)][ci]
# [ci]: https://travis-ci.org/Solistra/ruby-digest
# 
# Summary
# -----------------------------------------------------------------------------
#   Ruby Digest aims to provide pure-Ruby implementations of the digest objects
# provided by the MRI Ruby 'digest' standard library (originally written as
# native C extensions). At present, Ruby Digest accurately implements the
# `MD5`, `SHA1`, and `SHA256` hashing algorithms, the Bubble Babble encoding,
# and the `HMAC` keyed-hash message authentication code.
# 
#   Ruby Digest has been provided primarily for Ruby environments which do not
# have access to native extensions for any reason (notable examples include
# the RPG Maker series and SketchUp Make).
# 
# Notes
# -----------------------------------------------------------------------------
#   While Ruby Digest aims to provide a reasonable, pure-Ruby alternative to
# the MRI Ruby 'digest' standard library, there are a few notable classes
# missing -- namely the `RMD160`, `SHA384`, and `SHA512` classes.
# 
# License
# -----------------------------------------------------------------------------
#   Ruby Digest is free and unencumbered software released into the public
# domain.
# 
#++

# Gel::Vendor::RubyDigest
# =============================================================================
# Provides a pure-Ruby implementation of the MRI 'digest' standard library.
module Gel::Vendor::RubyDigest
  # The semantic version of {Gel::Vendor::RubyDigest}.
  VERSION = '0.0.1pre'.freeze
  
  # A specifically-ordered array of lower-case vowels used to create Bubble
  # Babble-encoded digest hash values.
  VOWELS = %w( a e i o u y ).freeze
  
  # A specifically-ordered array of lower-case consonants used to create
  # Bubble Babble-encoded digest hash values.
  CONSONANTS = %w( b c d f g h k l m n p r s t v z x ).freeze
  
  # Encodes the given string in Bubble Babble (an encoding designed to be more
  # human-readable than hexadecimal).
  # 
  # @param string [String] the string to encode in Bubble Babble
  # @return [String] the Bubble Babble-encoded string
  # @see http://wiki.yak.net/589/Bubble_Babble_Encoding.txt
  def self.bubblebabble(string)
    d      = string
    seed   = 1
    babble = 'x'
    length = d.length
    rounds = (length / 2) + 1
    0.upto(rounds - 1) do |i|
      if i + 1 < (rounds || length % 2)
        i0 = (((d[2 * i].ord >> 6) & 3) + seed) % 6
        i1 = (d[2 * i].ord >> 2) & 15
        i2 = ((d[2 * i].ord & 3) + seed / 6) % 6
        babble << "#{VOWELS[i0]}#{CONSONANTS[i1]}#{VOWELS[i2]}"
        if (i + 1 < rounds)
          i0 = (d[2 * i + 1].ord >> 4) & 15
          i1 = d[2 * i + 1].ord & 15
          babble << "#{CONSONANTS[i0]}-#{CONSONANTS[i1]}"
          seed = ((seed * 5) + (d[2 * i].ord * 7) + d[2 * i + 1].ord) % 36
        end
      else
        if length.even?
          babble << "#{VOWELS[seed % 6]}#{CONSONANTS[16]}#{VOWELS[seed / 6]}"
        else
          i0 = (((d[length - 1].ord >> 6) & 3) + seed) % 6
          i1 = (d[length - 1].ord >> 2) & 15
          i2 = (((d[length - 1].ord) & 3) + seed / 6) % 6
          babble << "#{VOWELS[i0]}#{CONSONANTS[i1]}#{VOWELS[i2]}"
        end
      end
    end
    babble << 'x'
  end
  
  # Generates a hex-encoded version of the given `string`.
  # 
  # @param string [String] the string to hex-encode
  # @return [String] the hex-encoded string
  def self.hexencode(string)
    string.unpack('H*').pack('A*')
  end
  
  # Instance
  # ===========================================================================
  # Provides instance methods for a digest implementation object to calculate
  # message digest values.
  module Instance
    # If a string is given, checks whether or not it is equal to the hex-
    # encoded hash value of this digest object. If another digest instance is
    # given, checks whether or not they have the same hexadecimal hash value.
    # 
    # @param other [Object] the other object to compare this digest to
    # @return [Boolean] `true` if both objects have matching digest values,
    #   `false` otherwise
    def ==(other)
      hexdigest == (other.respond_to?(:hexdigest) ? other.hexdigest : other)
    end
    
    # @raise [RuntimeError] if a subclass does not implement this method
    def block_length
      raise RuntimeError, "#{self.class} does not implement block_length()"
    end
    
    # @raise [RuntimeError] if a subclass does not implement this method
    def digest_length
      raise RuntimeError, "#{self.class} does not implement digest_length()"
    end
    alias_method :length, :digest_length
    alias_method :size,   :length
    
    # Returns the resulting base64-encoded hash value of the digest if no
    # string is given, maintaining the digest's state. If a string is given,
    # returns the base64-encoded hash value of the given string, resetting the
    # digest to its initial state.
    # 
    # @param str [String, nil] the string to produce a base64-encoded hash
    #   value for if given
    # @return [String] the requested base64-encoded digest
    def base64digest(str = nil)
      str.nil? ? clone.base64digest! :
        new.update(str).base64digest!.tap { reset }
    end
    
    # Returns the resulting hash value in a base64-encoded form and resets the
    # digest to its initial state.
    # 
    # @return [String] the base64-encoded hash value of this digest object
    #   before the reset
    def base64digest!
      [finish].pack('m0').tap { reset }
    end
    
    # @return [String] the Bubble Babble-encoded hash value of this digest
    #   object
    # @see Gel::Vendor::RubyDigest.bubblebabble
    def bubblebabble
      Gel::Vendor::RubyDigest.bubblebabble(digest)
    end
    
    # Returns the resulting hash value of the digest if no string is given,
    # maintaining the digest's state. If a string is given, returns the hash
    # value of the given string, resetting the digest to its initial state.
    # 
    # @param str [String, nil] the string to produce a hash value for if given
    # @return [String] the requested digest
    def digest(str = nil)
      str.nil? ? clone.digest! : new.update(str).digest!.tap { reset }
    end
    
    # Returns the resulting hash value and resets the digest object to its
    # initial state.
    # 
    # @return [String] the hash value of this digest object before the reset
    def digest!
      finish.tap { reset }
    end
    
    # Updates this digest with the contents of the given `filename` and returns
    # the updated digest object.
    # 
    # @param filename [String] the path to a file used to update the digest
    # @return [self] the updated digest instance
    def file(filename)
      File.open(filename, 'rb') do |file|
        buffer = ''
        update(buffer) while file.read(16384, buffer)
      end
      self
    end
    
    # @raise [RuntimeError] if a subclass does not implement this method
    def finish
      raise RuntimeError, "#{self.class} does not implement finish()"
    end
    private :finish
    
    # Returns the resulting hex-encoded hash value of the digest if no string
    # is given, maintaining the digest's state. If a string is given, returns
    # the hex-encoded hash value of the given string, resetting the digest to
    # its initial state.
    # 
    # @param str [String, nil] the string to produce a hex-encoded hash value
    #   for if given
    # @return [String] the requested hex-encoded digest
    def hexdigest(str = nil)
      str.nil? ? clone.hexdigest! : new.update(str).hexdigest!.tap { reset }
    end
    
    # Returns the resulting hash value in a hex-encoded form and resets the
    # digest object to its initial state.
    # 
    # @return [String] the hex-encoded hash value of this digest object before
    #   the reset
    def hexdigest!
      finish.unpack('H*').pack('A*').tap { reset }
    end
    
    # @return [Gel::Vendor::RubyDigest::Class] a new, initialized copy of this digest object
    def new
      clone.reset
    end
    
    # @raise [RuntimeError] if a subclass does not implement this method
    def reset
      raise RuntimeError, "#{self.class} does not implement reset()"
    end
    
    # @return [String] the hex-encoded hash value of this digest object
    def to_s
      hexdigest
    end
    
    # @raise [RuntimeError] if a subclass does not implement this method
    def update(string)
      raise RuntimeError, "#{self.class} does not implement update()"
    end
    alias_method :<<, :update
  end
  # Class
  # ===========================================================================
  # Stands as a base class for digest implementation classes.
  class Class
    include Instance
    
    # The 8-bit field used for bitwise `AND` masking. Defaults to `0xFFFFFFFF`.
    MASK = 0xFFFFFFFF
    
    # Hashes the given string, returning the base64-encoded digest.
    # 
    # @param string [String] the string to generate a base64-encoded digest for
    # @return [String] the base64-encoded digest of the given string
    def self.base64digest(string, *arguments)
      new(*arguments).update(string).base64digest!
    end
    
    # Hashes the given string, returning the Bubble Babble-encoded digest.
    # 
    # @param string [String] the string generate a Bubble Babble-encoded digest
    #   for
    # @return [String] the Bubble Babble-encoded digest of the given string
    # @see Gel::Vendor::RubyDigest.bubblebabble
    def self.bubblebabble(string)
      Gel::Vendor::RubyDigest.bubblebabble(digest(string))
    end
    
    # Hashes the given string, returning the digest.
    # 
    # @param string [String] the string to generate a digest for
    # @return [String] the digest of the given string
    def self.digest(string, *arguments)
      new(*arguments).update(string).digest!
    end
    
    # Hashes the given string, returning the hex-encoded digest.
    # 
    # @param string [String] the string to generate a hex-encoded digest for
    # @return [String] the hex-encoded digest of the given string
    def self.hexdigest(string, *arguments)
      new(*arguments).update(string).hexdigest!
    end
    
    # Generates a new digest object representing the hashed contents of the
    # given file.
    #
    # @param filename [String] the path to a file to generate a digest object
    #   for
    # @return [Base] a new digest object representing the hashed contents of
    #   the given file
    def self.file(filename, *arguments)
      new(*arguments).file(filename)
    end
  end
  # Base
  # ===========================================================================
  # Abstract class providing a common interface to message digest
  # implementation classes.
  class Base < Class
    # Customizes object instantiation to raise a `NotImplementedError` if the
    # object to be initialized is a {Gel::Vendor::RubyDigest::Base} object.
    # 
    # @param args [Array<Object>] the arguments to pass to `#initialize`
    # @return [Gel::Vendor::RubyDigest::Base] the new digest object instance
    # @raise [NotImplementedError] if the requested digest object is exactly
    #   {Gel::Vendor::RubyDigest::Base}
    def self.new(*args, &block)
      instance = super
      if instance.class == Base
        raise NotImplementedError, "#{self} is an abstract class"
      end
      instance
    end
    
    # Defaults to the length of the {#digest} value for this digest object.
    # 
    # @return [Fixnum] the length of the hash value of this digest object
    def digest_length
      digest.length
    end
    
    # Initializes a new digest object with an empty initial state.
    # 
    # @return [self] the new digest object
    def initialize
      @buffer = ''
    end
    
    # Customizes duplication of this digest object, properly setting the buffer
    # of the duplicate to a copy of the source object's buffer.
    # 
    # @note This method exists so that duplicate digest objects do not refer to
    #   the same base string buffer as the source digest object.
    # 
    # @param source [Gel::Vendor::RubyDigest::Base] the digest object being duplicated
    # @return [Gel::Vendor::RubyDigest::Base] the duplicate digest object
    def initialize_copy(source)
      super
      @buffer = source.instance_eval { @buffer.clone }
    end
    
    # @return [String] a human-readable representation of this digest object
    def inspect
      "#<#{self.class.name}: #{hexdigest}>"
    end
    
    # Updates the digest with the given `string`, returning the updated digest
    # instance.
    # 
    # @param string [String] the string to update the digest with
    # @return [self] the updated digest instance
    # @raise [TypeError] if the given `string` is not a string
    def update(string)
      unless string.kind_of?(String)
        raise TypeError, "can't convert #{string.class.inspect} into String"
      end
      tap { @buffer << string }
    end
    alias_method :<<, :update
    
    # Resets the digest object to its initial state and returns the digest
    # instance.
    # 
    # @return [self] the reset digest instance
    def reset
      tap { @buffer.clear }
    end
  end
  # MD5
  # ===========================================================================
  # Provides a pure-Ruby implementation of an MD5 digest object.
  class MD5 < Base
    # The initial constant values for the 32-bit constant words A, B, C, and D,
    # respectively.
    @@words = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476]
    
    # Generate and store the initial constant values used by the MD5 algorithm
    # to mutate data -- all of this information is directly used in the
    # `.hexdigest` method of this class.
    @@initial_values = lambda do |f, t, k, s, n4|
      1.upto(64) do |i|
        t[i]  = (Math.sin(i).abs * 0x100000000).truncate
        n4[i] = Array.new(4) { |j| ((65 - i) + j) % 4 }
        case i
        when 1..16
          f[i] = lambda { |x, y, z| (x & y) | ((~x) & z) }
          k[i] = i - 1
          s[i] = [7, 12, 17, 22][(i - 1) % 4]
        when 17..32
          f[i] = lambda { |x, y, z| (x & z) | (y & (~z)) }
          k[i] = (1 + (i - 17) * 5) % 16
          s[i] = [5, 9, 14, 20][(i - 1) % 4]
        when 33..48
          f[i] = lambda { |x, y, z| x ^ y ^ z }
          k[i] = (5 + (i - 33) * 3) % 16
          s[i] = [4, 11, 16, 23][(i - 1) % 4]
        when 49..64
          f[i] = lambda { |x, y, z| y ^ (x | (~z)) }
          k[i] = ((i - 49) * 7) % 16
          s[i] = [6, 10, 15, 21][(i - 1) % 4]
        end
      end
      [f, t, k, s, n4]
    end.call(*Array.new(5) { [] })
    
    # @return [64] MD5 digests always have a block length of 64 bytes
    def block_length
      64
    end
    
    # @return [16] MD5 digests always have a length of 16 bytes
    def digest_length
      16
    end
    alias_method :length, :digest_length
    alias_method :size,   :length
    
    # Hashes the buffer of this MD5 digest object, returning the computed hash
    # value.
    # 
    # @return [String] the hash value of this MD5 digest object
    def finish
      words          = @@words.dup
      f, t, k, s, n4 = *@@initial_values
      generate_split_buffer(@buffer) do |chunk|
        words2 = words.dup
        1.upto(64) do |r|
          words[n4[r][0]] = MASK & (words[n4[r][0]] + 
            f[r].call(*n4[r][1..3].map { |e| words[e] }) + chunk[k[r]] + t[r])
          words[n4[r][0]] = rotate(words[n4[r][0]], s[r])
          words[n4[r][0]] = MASK & (words[n4[r][0]] + words[n4[r][1]])
        end
        words.map!.with_index { |word, index| MASK & (word + words2[index]) }
      end
      words.reduce('') do |digest, word|
        digest << [MASK & word].pack('V')
      end.tap { reset }
    end
    private :finish
    
    # Generates a split buffer of string values used to perform the main loop
    # of the hashing algorithm.
    # 
    # @param string [String] the base string to generate a split buffer from
    # @yieldreturn [String] each chunk of the split buffer
    # @return [Array<String>] the split buffer
    def generate_split_buffer(string)
      size   = string.size * 8
      buffer = string + ['10000000'].pack('B8')
      buffer << [0].pack('C') while buffer.size % 64 != 56
      buffer << [MASK & size].pack('V') + [size >> 32].pack('V')
      split  = [].tap do |a|
        (buffer.size / 64).times { |i| a[i] = buffer[i*64,64].unpack('V16') }
      end
      block_given? ? split.each { |chunk| yield chunk } : split
    end
    private :generate_split_buffer
    
    # Binary left-rotates the given `value` by the given number of `spaces`.
    # 
    # @param value [Fixnum] the value to binary left-rotate
    # @param spaces [Fixnum] the number of spaces to shift to the left
    # @return [Fixnum] the left-rotated value
    def rotate(value, spaces)
      value << spaces | value >> (32 - spaces)
    end
    private :rotate
  end
  # SHA1
  # ===========================================================================
  # Provides a pure-Ruby implementation of an SHA1 digest object.
  class SHA1 < Base
    # The initial constant values for the 32-bit constant words A, B, C, D, and
    # E, respectively.
    @@words = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
    
    # @return [64] SHA1 digests always have a block length of 64 bytes
    def block_length
      64
    end
    
    # @return [20] SHA1 digests always have a length of 20 bytes
    def digest_length
      20
    end
    alias_method :length, :digest_length
    alias_method :size,   :length
    
    # Hashes the buffer of this SHA1 digest object, returning the computed hash
    # value.
    # 
    # @return [String] the hash value of this SHA1 digest object
    def finish
      words = @@words.dup
      generate_split_buffer(@buffer) do |chunk|
        w = []
        a, b, c, d, e = *words
        chunk.each_slice(4) do |a, b, c, d|
          w << (((a << 8 | b) << 8 | c) << 8 | d)
        end
        (16..79).map do |i|
          w[i] = MASK & rotate((w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]), 1)
        end
        0.upto(79) do |i|
          f, k = case i
          when  0..19 then [((b & c) | (~b & d)), 0x5A827999]
          when 20..39 then [(b ^ c ^ d), 0x6ED9EBA1]
          when 40..59 then [((b & c) | (b & d) | (c & d)), 0x8F1BBCDC]
          when 60..79 then [(b ^ c ^ d), 0xCA62C1D6]
          end
          t = MASK & (MASK & rotate(a, 5) + f + e + k + w[i])
          a, b, c, d, e = t, a, MASK & rotate(b, 30), c, d
        end
        mutated = [a, b, c, d, e]
        words.map!.with_index { |word, index| MASK & (word + mutated[index]) }
      end
      words.reduce('') do |digest, word|
        digest << [word].pack('N')
      end.tap { reset }
    end
    private :finish
    
    # Generates a split buffer of integer values used to perform the main loop
    # of the hashing algorithm.
    # 
    # @param string [String] the base string to generate a split buffer from
    # @yieldreturn [Array<Fixnum>] each 64-element chunk of the split buffer
    # @return [Array<Fixnum>] the split buffer
    def generate_split_buffer(string)
      size   = string.size * 8
      buffer = string + ['10000000'].pack('B8')
      buffer << [0].pack('C') while buffer.size % 64 != 56
      buffer << [size].pack('Q').reverse
      buffer = buffer.unpack('C*')
      block_given? ? buffer.each_slice(64) { |chunk| yield chunk } : buffer
    end
    private :generate_split_buffer
    
    # Binary left-rotates the given `value` by the given number of `spaces`.
    # 
    # @param value [Fixnum] the value to binary left-rotate
    # @param spaces [Fixnum] the number of spaces to shift to the left
    # @return [Fixnum] the left-rotated value
    def rotate(value, spaces)
      value << spaces | value >> (32 - spaces)
    end
    private :rotate
  end
  # SHA256
  # ===========================================================================
  # Provides a pure-Ruby implementation of an SHA256 digest object.
  class SHA256 < Base
    # The initial constant values for the 32-bit constant words A, B, C, D, E,
    # F, G, and H, respectively.
    @@words = [
      0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
      0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
    ]
    
    # The constant values used for word mutation each round.
    # 
    # @note There are 64 rounds per mutation for the SHA256 algorithm.
    @@rounds = [
      0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1,
      0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
      0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786,
      0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
      0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147,
      0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
      0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B,
      0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
      0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A,
      0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
      0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    ]
    
    # @return [64] SHA256 digests always have a block length of 64 bytes
    def block_length
      64
    end
    
    # @return [32] SHA256 digests always have a length of 32 bytes
    def digest_length
      32
    end
    alias_method :length, :digest_length
    alias_method :size,   :length
    
    # Hashes the buffer of this SHA256 digest object, returning the computed
    # hash value.
    # 
    # @return [String] the hash value of this SHA256 digest object
    def finish
      words = @@words.dup
      generate_split_buffer(@buffer) do |chunk|
        w = []
        a, b, c, d, e, f, g, h, = *words
        chunk.each_slice(4) do |a, b, c, d|
          w << (((a << 8 | b) << 8 | c) << 8 | d)
        end
        16.upto(63) do |i|
          s0 = rotate(w[i - 15], 7) ^ rotate(w[i - 15], 18) ^ (w[i - 15] >> 3)
          s1 = rotate(w[i - 2], 17) ^ rotate(w[i - 2], 19) ^ (w[i - 2] >> 10)
          w[i] = MASK & (w[i - 16] + s0 + w[i - 7] + s1)
        end
        0.upto(63) do |i|
          s0  = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
          maj = (a & b) ^ (a & c) ^ (b & c)
          t2  = MASK & (s0 + maj)
          s1  = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
          ch  = (e & f) ^ ((~e) & g)
          t1  = MASK & (h + s1 + ch + @@rounds[i] + w[i])
          tmp1 = MASK & (t1 + t2)
          tmp2 = MASK & (d  + t1)
          a, b, c, d, e, f, g, h = tmp1, a, b, c, tmp2, e, f, g
        end
        mutated = [a, b, c, d, e, f, g, h]
        words.map!.with_index { |word, index| MASK & (word + mutated[index]) }
      end
      words.reduce('') do |digest, word|
        digest << [word].pack('N')
      end.tap { reset }
    end
    private :finish
    
    # Generates a split buffer of integer values used to perform the main loop
    # of the hashing algorithm.
    # 
    # @param string [String] the base string to generate a split buffer from
    # @yieldreturn [Array<Fixnum>] each 64-element chunk of the split buffer
    # @return [Array<Fixnum>] the split buffer
    def generate_split_buffer(string)
      size = string.size * 8
      buffer = string + ['10000000'].pack('B8')
      buffer << [0].pack('C') while buffer.size % 64 != 56
      buffer << [size].pack('Q').reverse
      buffer = buffer.unpack('C*')
      block_given? ? buffer.each_slice(64) { |chunk| yield chunk } : buffer
    end
    private :generate_split_buffer
    
    # Binary right-rotates the given `value` by the given number of `spaces`.
    # 
    # @param value [Fixnum] the value to binary right-rotate
    # @param spaces [Fixnum] the number of spaces to shift to the right
    # @return [Fixnum] the right-rotated value
    def rotate(value, spaces)
      value >> spaces | value << (32 - spaces)
    end
    private :rotate
  end
  # SHA2
  # ===========================================================================
  # Provides a wrapper class for the SHA2 family of digest objects.
  class SHA2 < Class
    # Delegates calls to `#block_length` to the underlying SHA2 digest object.
    # 
    # @return [Fixnum] the block length of the digest object
    def block_length
      @sha2.block_length
    end
    
    # Delegates calls to `#digest_length` to the underlying SHA2 digest object.
    # 
    # @return [Fixnum] the digest length of the digest object
    def digest_length
      @sha2.digest_length
    end
    alias_method :length, :digest_length
    alias_method :size,   :length
    
    # Delegates calls to `#finish` to the underlying SHA2 digest object's
    # `#digest!` instance method.
    # 
    # @return [String] the resulting hash value of the digest object
    def finish
      @sha2.digest!
    end
    private :finish
    
    # Initializes a new {SHA2} digest object of the given `bit_length` with an
    # empty initial state.
    # 
    # @param bit_length [Fixnum] the desired SHA2 digest length in bits
    # @return [self] the new {SHA2} instance
    # @raise [ArgumentError] if an invalid digest bit length is requested
    def initialize(bit_length = 256)
      case bit_length
      when 256 then @sha2 = Gel::Vendor::RubyDigest::SHA256.new
      else
        raise ArgumentError, "unsupported bit length: #{bit_length.inspect}"
      end
      @sha2.send(:initialize)
      @bit_length = bit_length
    end
    
    # Customizes duplication of this {SHA2} object, properly setting the digest
    # object of the duplicate to a copy of the source object's digest object.
    # 
    # @note This method exists so that duplicate {SHA2} objects do not refer to
    #   the same base digest object as the source digest object.
    # 
    # @param source [Gel::Vendor::RubyDigest::SHA2] the {SHA2} object being duplicated
    # @return [Gel::Vendor::RubyDigest::SHA2] the duplicate {SHA2} object
    def initialize_copy(source)
      super
      @sha2 = source.instance_eval { @sha2.clone }
    end
    
    # @return [String] a human-readable representation of this {SHA2} instance
    def inspect
      "#<#{self.class.name}:#{@bit_length} #{hexdigest}>"
    end
    
    # Delegates calls to `#reset` to the underlying SHA2 digest object.
    # 
    # @return [self] the reset {SHA2} instance
    def reset
      tap { @sha2.reset }
    end
    
    # Delegates calls to `#update` to the underlying SHA2 digest object.
    # 
    # @param string [String] the string to update the digest with
    # @return [self] the updated {SHA2} instance
    def update(string)
      tap { @sha2.update(string) }
    end
    alias_method :<<, :update
  end
  # HMAC
  # ===========================================================================
  # Provides a keyed-hash message authentication code object.
  class HMAC < Class
    # Delegates calls to `#block_length` to the underlying digest object.
    # 
    # @return [Fixnum] the block length of the digest object
    def block_length
      @md.block_length
    end
    
    # Delegates calls to `#digest_length` to the underlying digest object.
    # 
    # @return [Fixnum] the digest length of the digest object
    def digest_length
      @md.digest_length
    end
    alias_method :length, :digest_length
    alias_method :size,   :length
    
    # Delegates calls to `#finish` to the underlying digest object, properly
    # managing the digest object's buffer for `HMAC`.
    # 
    # @return [String] the resulting hash value of the digest object
    def finish
      original = @md.digest!
      @md.update(@opad).update(original).digest!
    end
    private :finish
    
    # Initializes a new keyed-hash message authentication code ({HMAC}) object
    # with the given key and digest object.
    # 
    # @note {HMAC} objects are significantly more secure than an individual
    #   hashing algorithm on its own.
    # 
    # @param key [String] the key for this {HMAC} object
    # @param digest_class [Gel::Vendor::RubyDigest::Base] the digest object for this {HMAC}
    def initialize(key, digest_class)
      @md = digest_class.new
      
      length = @md.block_length
      key    = @md.digest(key) if key.bytesize > length
      ipad   = Array.new(length, 0x36) # Inner HMAC padding.
      opad   = Array.new(length, 0x5C) # Outer HMAC padding.
      
      key.bytes.each_with_index do |character, index|
        ipad[index] ^= character
        opad[index] ^= character
      end
      
      @key  = key.freeze
      @ipad = ipad.pack('C*').freeze
      @opad = opad.pack('C*').freeze
      @md.update(@ipad)
    end
    
    # Customizes duplication of this {HMAC} object, properly setting the digest
    # object of the duplicate to a copy of the source object's digest object.
    # 
    # @note This method exists so that duplicate {HMAC} objects do not refer to
    #   the same base digest object as the source digest object.
    # 
    # @param source [Gel::Vendor::RubyDigest::HMAC] the {HMAC} object being duplicated
    # @return [Gel::Vendor::RubyDigest::HMAC] the duplicate {HMAC} object
    def initialize_copy(source)
      super
      @md = source.instance_eval { @md.clone }
    end
    
    # @return [String] a human-readable representation of this {HMAC} instance
    def inspect
      digest = @md.inspect.sub(/^\#<(.*)>$/) { $1 }
      "#<#{self.class.name}: key=#{@key.inspect} digest=#{digest}>"
    end
    
    # Delegates calls to `#reset` to the underlying digest object, properly
    # updating its contents with the ipad of this {HMAC} object.
    # 
    # @return [self] the reset {HMAC} instance
    def reset
      tap { @md.reset.update(@ipad) }
    end
    
    # Delegates calls to `#update` to the underlying digest object.
    # 
    # @param string [String] the string to update the digest with
    # @return [self] the updated {HMAC} instance
    def update(string)
      tap { @md.update(string) }
    end
    alias_method :<<, :update
  end
end
