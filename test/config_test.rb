# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  def test_reading_key_from_config_successully
    prev_gel_config = ENV['GEL_CONFIG']
    ENV['GEL_CONFIG'] = fixture_file('')
    klass = Gel::Config.new
    assert_equal '316429e', klass['packages.example.io']
    ENV['GEL_CONFIG'] = prev_gel_config
  end

  def test_reading_group_key_from_config_successully
    prev_gel_config = ENV['GEL_CONFIG']
    ENV['GEL_CONFIG'] = fixture_file('')
    klass = Gel::Config.new
    assert_equal '316429e', klass['packages', 'example.io']
    ENV['GEL_CONFIG'] = prev_gel_config
  end

  def test_reading_uppercase_key_from_config_successully
    prev_gel_config = ENV['GEL_CONFIG']
    ENV['GEL_CONFIG'] = fixture_file('')
    klass = Gel::Config.new
    assert_equal 'true', klass['gem.MIT']
    ENV['GEL_CONFIG'] = prev_gel_config
  end

  def test_reading_all_from_config_successully
    prev_gel_config = ENV['GEL_CONFIG']
    ENV['GEL_CONFIG'] = fixture_file('')
    settings = Gel::Config.new.all
    assert_equal '316429e', settings['packages.example.io']
    assert_equal 'true', settings['gem.mit']
    assert_equal '10', settings['timeout']
    ENV['GEL_CONFIG'] = prev_gel_config
  end
end
