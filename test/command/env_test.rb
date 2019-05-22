# frozen_string_literal: true

require "test_helper"

class EnvTest < Minitest::Test
  def test_help
    output = capture_stdout { Gel::Command::Env.run(["env"]) }

    assert output =~ %r{## Gel}
    assert output =~ %r{## User}
    assert output =~ %r{## Ruby}
    assert output =~ %r{## Relevant Files}
  end
end
