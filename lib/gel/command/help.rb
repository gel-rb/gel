# frozen_string_literal: true

class Gel::Command::Help < Gel::Command
  def run(_command_line)
    puts <<~HELP
      Gel is a modern gem manager.

      Usage:
        gel help       Print this help message.
        gel install    Install the gems from Gemfile.
        gel lock       Update lockfile without installing.
        gel exec       Run command in context of the gel.

      Further information:
        https://gel.dev/
    HELP
  end
end
