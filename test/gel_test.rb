# frozen_string_literal: true

require "test_helper"

class GelTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Gel::VERSION
  end

  def test_tests_cannot_see_rubygems_runtime
    assert_nil defined?(::Gem.default_exec_format)
  end

  def test_tests_cannot_see_bundler_runtime
    assert_nil defined?(::Bundler)
  end

  def test_tests_dont_have_rubygems_loaded
    assert_empty $".grep(/(?<!compatibility\/|pub_grub\/)rubygems\.rb$/i)
  end
end
