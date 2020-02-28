# frozen_string_literal: true

require "test_helper"

class HelpTest < Minitest::Test
  def test_help
    output = capture_stdout { Gel::Command::Version.run(["--version"]) }

    assert output =~ %r{Gel version}
  end
end
