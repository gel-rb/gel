# frozen_string_literal: true

require "test_helper"

class EnvTest < Minitest::Test
  def test_env
    output = capture_stdout { Gel::Command::Env.run(["env"]) }

    assert output =~ %r{## Gel}
    assert output =~ %r{## User}
    assert output =~ %r{## Ruby}
  end

  def test_env_with_full
    output = capture_stdout { Gel::Command::Env.run(["env", "--full"]) }

    assert output =~ %r{## Gel}
    assert output =~ %r{## User}
    assert output =~ %r{## Ruby}
    assert output =~ %r{## Relevant Files}
  end
end
