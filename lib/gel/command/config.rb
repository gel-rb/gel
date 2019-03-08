# frozen_string_literal: true

class Gel::Command::Config < Gel::Command
  def run(command_line)
    if command_line.size == 1
      puts Gel::Environment.config[command_line.first]
    else
      Gel::Environment.config[command_line.shift] = command_line.join(" ")
    end
  end
end
