# frozen_string_literal: true

class Gel::Command::Ruby < Gel::Command
  def run(command_line)
    command = Gel::Command::Exec.new
    command.run(["ruby", *command_line])
  ensure
    self.reraise = command.reraise if command
  end
end
