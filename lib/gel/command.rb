# frozen_string_literal: true

require_relative "compatibility"
require_relative "error"

class Gel::Command
  def self.run(command_line)
    command_line = command_line.dup
    if command_name = extract_word(command_line)
      const = command_name.downcase.sub(/^./, &:upcase).gsub(/[-_]./) { |s| s[1].upcase }
      if Gel::Command.const_defined?(const, false)
        command = Gel::Command.const_get(const, false).new
        command.run(command_line)
      elsif Gel::Environment.activate_for_executable(["gel-#{command_name}", command_name])
        command_name = "gel-#{command_name}" if Gel::Environment.find_executable("gel-#{command_name}")
        command = Gel::Command::Exec.new
        command.run([command_name, *command_line])
      else
        raise "Unknown command #{command_name.inspect}"
      end
    else
      raise "No subcommand specified"
    end
  rescue Gel::ReportableError => ex
    raise if $DEBUG || (command && command.reraise)

    $stderr.puts "ERROR: #{ex.message}"
    if more = ex.details
      $stderr.puts more
    end

    exit ex.exit_code
  rescue Interrupt => ex
    raise if $DEBUG || (command && command.reraise)

    # Re-signal so our parent knows why we died
    Signal.trap(ex.signo, "SYSTEM_DEFAULT")
    Process.kill(ex.signo, Process.pid)

    # Shouldn't be reached
    raise
  rescue SystemExit, SignalException
    raise
  rescue StandardError, ScriptError, NoMemoryError, SystemStackError => ex
    raise if $DEBUG || (command && command.reraise)

    # We want basically everything here: we definitely care about
    # StandardError and ScriptError... but we also assume that whatever
    # caused NoMemoryError or SystemStackError was way down the call
    # stack, so we've now unwound enough to safely handle even those.

    $stderr.print "\n\n===== Gel Internal Error =====\n\n"

    # We'll improve this later, but for now after the header we'll leave
    # ruby to write the message & backtrace:
    raise
  end

  def self.extract_word(arguments)
    if idx = arguments.index { |w| w =~ /^[^-]/ }
      arguments.delete_at(idx)
    end
  end

  # If set to true, an error raised from #run will pass straight up to
  # ruby instead of being treated as an internal Gel error
  attr_accessor :reraise
end

require_relative "command/help"
require_relative "command/install"
require_relative "command/install_gem"
require_relative "command/env"
require_relative "command/exec"
require_relative "command/lock"
require_relative "command/ruby"
require_relative "command/stub"
require_relative "command/config"
require_relative "command/shell_setup"
