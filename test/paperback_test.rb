require "test_helper"

class PaperbackTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Paperback::VERSION
  end

  def test_tests_cannot_see_rubygems
    assert_nil defined?(::Gem)
  end
end
