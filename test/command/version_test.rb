# frozen_string_literal: true

require "test_helper"

class VersionTest < Minitest::Test
  def test_version
    output = capture_stdout { Gel::Command::Version.run(["--version"]) }

    assert output =~ %r{Gel version}
  end
end
