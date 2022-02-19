# frozen_string_literal: true

class Gel::Command::Stub < Gel::Command
  def run(command_line)
    arguments = command_line.dup

    stub_command = arguments.shift

    # Newer stubs have 'ruby' as an extra noise word for `ruby -S` support
    stub_command = arguments.shift if stub_command == "ruby"

    # We don't need the shebang-added path to the binstub
    arguments.shift

    command = Gel::Command::Exec.new
    command.run([stub_command, *arguments], from_stub: true)
  ensure
    self.reraise = command.reraise if command
  end
end
