# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ConfigTest < Minitest::Test
  def test_reading_configuration
    ENV["GEL_AUTH"] = "http://user:pass@ruby.example.com http://user2:pass2@gems.example.org"

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
    assert_equal "user:pass", config["ruby.example.com"]
    assert_equal "user2:pass2", config["gems.example.org"]
  ensure
    ENV.delete("GEL_AUTH")
  end
end
