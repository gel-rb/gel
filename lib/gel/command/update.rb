# frozen_string_literal: true

class Gel::Command::Update < Gel::Command
  def run(command_line)
    # Mega update mode
    command_line = ["--major"] if command_line.empty?

    Gel::Command::Lock.new.run(command_line)
    Gel::Environment.activate(install: true, output: $stderr)
  end
end
