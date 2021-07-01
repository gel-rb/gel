# frozen_string_literal: true

class Gel::Command::Config < Gel::Command
  def run(command_line)
    if command_line.empty?
      Gel::Environment.config.all.each do |key,_|
        value = Gel::Environment.config[key]
        puts "#{key}=#{value}"
      end
    elsif command_line.size == 1
      puts Gel::Environment.config[command_line.first]
    else
      Gel::Environment.config[command_line.shift] = command_line.join(" ")
    end
  end
end
