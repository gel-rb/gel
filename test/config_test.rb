# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  def test_reading_single_item_from_config_successully
    config = Class.new(Gel::Config) do
      define_method(:config_file) do
        File.open(fixture_file("config")).read
      end

      define_method(:config_exists?) do
        true
      end
    end

    klass = config.new
    assert_equal '1', klass['jobs']
    assert_equal 'true', klass['gem.mit']
  end

  def test_reading_all_from_config_successully
    config = Class.new(Gel::Config) do
      define_method(:config_file) do
        File.open(fixture_file("config")).read
      end

      define_method(:config_exists?) do
        true
      end
    end

    output = config.new.all
    assert output['jobs'] == { '' => '1' }
    assert output['gem'] == { 'mit' => 'true' }
  end
end
