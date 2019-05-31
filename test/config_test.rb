# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  def test_reading_single_item_from_config_successully
    prev_gel_config = ENV['GEL_CONFIG']
    ENV['GEL_CONFIG'] = fixture_file('')
    klass = Gel::Config.new
    assert_equal '1', klass['jobs']
    assert_equal 'true', klass['gem.mit']
    ENV['GEL_CONFIG'] = prev_gel_config
  end

  def test_reading_all_from_config_successully
    prev_gel_config = ENV['GEL_CONFIG']
    ENV['GEL_CONFIG'] = fixture_file('')
    output = Gel::Config.new.all
    assert output['jobs'] == { '' => '1' }
    assert output['gem'] == { 'mit' => 'true' }
    ENV['GEL_CONFIG'] = prev_gel_config
  end
end
