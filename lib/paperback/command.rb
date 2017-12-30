# frozen_string_literal: true

class Paperback::Command
  def self.run(command_line)
    command_line = command_line.dup
    if command = extract_word(command_line)
      const = command.downcase.sub(/^./, &:upcase)
      if Paperback::Command.const_defined?(const)
        Paperback::Command.const_get(const).new.run(command_line)
      else
        raise "Unknown command #{command.inspect}"
      end
    else
      raise "No subcommand specified"
    end
  end

  def self.extract_word(arguments)
    if idx = arguments.index { |w| w =~ /^[^-]/ }
      return arguments.delete_at(idx)
    end
  end
end

require_relative "command/help"
require_relative "command/install"
require_relative "command/env"
require_relative "command/exec"
require_relative "command/lock"
