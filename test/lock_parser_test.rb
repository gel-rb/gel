# frozen_string_literal: true

require "test_helper"

class LockParserTest < Minitest::Test
  EXAMPLE = <<LOCKFILE
GEM
  remote: https://rubygems.org/
  specs:
    ast (2.3.0)
    minitest (5.10.3)
    parallel (1.12.0)
    parser (2.4.0.0)
      ast (~> 2.2)
    powerpack (0.1.1)
    rainbow (2.2.2)
      rake
    rake (12.1.0)
    rubocop (0.50.0)
      parallel (~> 1.10)
      parser (>= 2.3.3.1, < 3.0)
      powerpack (~> 0.1)
      rainbow (>= 2.2.2, < 3.0)
      ruby-progressbar (~> 1.7)
      unicode-display_width (~> 1.0, >= 1.0.1)
    rubocop-rails (1.1.0)
      rubocop (~> 0.49)
    ruby-progressbar (1.9.0)
    unicode-display_width (1.3.0)

PLATFORMS
  ruby

DEPENDENCIES
  minitest
  rake
  rubocop-rails

RUBY VERSION
   ruby 2.6.3p62

BUNDLED WITH
   1.15.4
LOCKFILE

  def test_simple_parse
    parser = Gel::LockParser.new
    assert_equal [
      ["GEM", {
        "remote" => ["https://rubygems.org/"],
        "specs" => [
          ["ast (2.3.0)"],
          ["minitest (5.10.3)"],
          ["parallel (1.12.0)"],
          ["parser (2.4.0.0)", ["ast (~> 2.2)"]],
          ["powerpack (0.1.1)"],
          ["rainbow (2.2.2)", ["rake"]],
          ["rake (12.1.0)"],
          ["rubocop (0.50.0)", [
            "parallel (~> 1.10)",
            "parser (>= 2.3.3.1, < 3.0)",
            "powerpack (~> 0.1)",
            "rainbow (>= 2.2.2, < 3.0)",
            "ruby-progressbar (~> 1.7)",
            "unicode-display_width (~> 1.0, >= 1.0.1)"]],
          ["rubocop-rails (1.1.0)", ["rubocop (~> 0.49)"]],
          ["ruby-progressbar (1.9.0)"],
          ["unicode-display_width (1.3.0)"],
        ] }],
      ["PLATFORMS", ["ruby"]],
      ["DEPENDENCIES", ["minitest", "rake", "rubocop-rails"]],
      ["RUBY VERSION", ["ruby 2.6.3p62"]],
      ["BUNDLED WITH", ["1.15.4"]],
    ], parser.parse(EXAMPLE)
  end
end
