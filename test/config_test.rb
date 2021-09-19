# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ConfigTest < Minitest::Test
  def test_reading_configuration
    dir = Dir.mktmpdir
    File.write("#{dir}/config", <<-CONFIG)
build:
  nokogiri: --libdir=foo
  mysql2: --libdir=bar

# Gem server credentials
ruby-gems.example.com: username:password
    CONFIG

    config = Gel::Config.new(dir)

    assert_equal "--libdir=foo", config[:build, "nokogiri"]
    assert_equal "--libdir=bar", config[:build, "mysql2"]
    assert_equal "username:password", config["ruby-gems.example.com"]
  end
end
