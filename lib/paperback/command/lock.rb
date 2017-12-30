# frozen_string_literal: true

class Paperback::Command::Lock < Paperback::Command
  def run(command_line)
    Paperback::Environment.lock(output: $stderr)
  end
end
