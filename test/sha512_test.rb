# frozen_string_literal: true

require "test_helper"
require "gel/support/sha512"

require "digest/sha2"

class SHA512Test < Minitest::Test
  def test_matching_results
    assert_consistent_hashes("")
    assert_consistent_hashes(" ")
    assert_consistent_hashes("a")
    assert_consistent_hashes("abc")
    assert_consistent_hashes("abcdefghijklmnopqrstuvwxyz")
    assert_consistent_hashes("abcdefghijklmnopqrstuvwxyz" * 100)

    assert_consistent_hashes("\x00" * 100)
    assert_consistent_hashes("\x00" * 10_000)

    assert_consistent_hashes("\xFF" * 100)
    assert_consistent_hashes("\xFF" * 10_000)

    (0..256).each do |n|
      assert_consistent_hashes("a" * n)
    end

    assert_consistent_hashes(File.read(__FILE__))
  end

  def assert_consistent_hashes(input)
    assert_equal(Digest::SHA512.hexdigest(input), Gel::Support::SHA512.hexdigest(input))
  end
end
