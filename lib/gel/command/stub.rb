# frozen_string_literal: true

class Gel::Command::Stub < Gel::Command
  def run(command_line)
    stub_command, _path, *arguments = command_line

    command = Gel::Command::Exec.new
    command.run([stub_command, *arguments])
  ensure
    self.reraise = command.reraise if command
  end
end
