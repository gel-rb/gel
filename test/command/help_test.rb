# frozen_string_literal: true

require "test_helper"
require "gel/command"

class HelpTest < Minitest::Test
  def test_help
    output = capture_stdout { Gel::Command::Help.run(["help"]) }

    assert output =~ %r{Gel is a modern gem manager}
    assert output =~ %r{Usage}
    assert output =~ %r{https://gel.dev}
  end

  def test_help_flag
    output = capture_stdout { Gel::Command::Help.run(["--help"]) }

    assert output =~ %r{Gel is a modern gem manager}
    assert output =~ %r{Usage}
    assert output =~ %r{https://gel.dev}
  end
end
