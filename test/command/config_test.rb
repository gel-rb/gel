# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  def test_default_config
    # poor mans mocking when config is called, we use a path within the test
    output = capture_stdout { Gel::Command::Config.run(["config"]) }

    assert_equal 0, Gel::Environment.config.all
  end
end
