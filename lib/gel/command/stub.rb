# frozen_string_literal: true

class Gel::Command::Stub < Gel::Command
  def run(command_line)
    command = Gel::Command::Exec.new
    command.run(command_line, from_stub: true)
  ensure
    self.reraise = command.reraise if command
  end
end
