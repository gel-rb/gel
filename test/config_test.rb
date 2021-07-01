# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  def setup
    @old_gel_config_env = ENV['GEL_CONFIG']
    ENV['GEL_CONFIG'] = fixture_file('')
  end

  def teardown
    ENV['GEL_CONFIG'] = @old_gel_config_env
  end

  def test_reading_key_from_config_successully
    klass = Gel::Config.new
    assert_equal '316429e', klass['packages.example.io']
  end

  def test_reading_group_key_from_config_successully
    klass = Gel::Config.new
    assert_equal '316429e', klass['packages', 'example.io']
  end

  def test_reading_uppercase_key_from_config_successully
    klass = Gel::Config.new
    assert_equal 'true', klass['gem.MIT']
  end

  def test_reading_all_from_config_successully
    settings = Gel::Config.new.all
    assert_equal '316429e', settings['packages.example.io']
    assert_equal 'true', settings['gem.mit']
    assert_equal '10', settings['timeout']
  end
end
