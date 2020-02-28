# frozen_string_literal: true

class Gel::Command::Version < Gel::Command
  def run(_command_line)
    puts "Gel version #{Gel::VERSION}"
  end
end
