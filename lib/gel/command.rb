# frozen_string_literal: true

require_relative "compatibility"
require_relative "error"

class Gel::Command
  def self.run(command_line)
    command_line = command_line.dup
    if command_name = extract_word(command_line)
      const = command_name.downcase.sub(/^./, &:upcase).gsub(/[-_]./) { |s| s[1].upcase }
      if const =~ /\A[a-z]+\z/i
        if Gel::Command.const_defined?(const, false)
          command = Gel::Command.const_get(const, false).new
          command.run(command_line)
        elsif Gel::Environment.activate_for_executable(["gel-#{command_name}", command_name])
          command_name = "gel-#{command_name}" if Gel::Environment.find_executable("gel-#{command_name}")
          command = Gel::Command::Exec.new
          command.run([command_name, *command_line])
        else
          raise Gel::Error::UnknownCommandError.new(command_name: command_name)
        end
      elsif stub_name = own_stub_file?(command_name) || other_stub_file?(command_name)
        command = Gel::Command::Exec.new
        command.run([stub_name, *command_line], from_stub: true)
      else
        raise Gel::Error::UnknownCommandError.new(command_name: command_name)
      end
    elsif flag_constant = flags(command_line).first
      flag_constant.new.run(command_line)
    else
      puts <<~EOF
      Gel doesn't have a default command; please run `gel install`
      EOF
    end
  rescue Exception => ex
    raise if $DEBUG || (command && command.reraise)
    handle_error(ex)
  end

  def self.handle_error(ex)
    case ex
    when Gel::ReportableError
      $stderr.puts "ERROR: #{ex.message}"
      if more = ex.details
        $stderr.puts more
      end

      exit ex.exit_code
    when Interrupt
      # Re-signal so our parent knows why we died
      Signal.trap(ex.signo, "SYSTEM_DEFAULT")
      Process.kill(ex.signo, Process.pid)

      # Shouldn't be reached
      raise ex
    when SystemExit, SignalException
      raise ex
    when StandardError, ScriptError, NoMemoryError, SystemStackError
      # We want basically everything here: we definitely care about
      # StandardError and ScriptError... but we also assume that whatever
      # caused NoMemoryError or SystemStackError was way down the call
      # stack, so we've now unwound enough to safely handle even those.

      $stderr.print "\n\n===== Gel Internal Error =====\n\n"

      # We'll improve this later, but for now after the header we'll leave
      # ruby to write the message & backtrace:
      raise ex
    else
      raise ex
    end
  end

  def self.extract_word(arguments)
    if idx = arguments.index { |w| w =~ /^[^-]/ }
      arguments.delete_at(idx)
    end
  end

  def self.own_stub_file?(path)
    # If it's our own stub file, we can skip reading and parsing it, and
    # just trust that the basename is correct.
    if Gel::Environment.store.stub_set.own_stub?(path)
      File.basename(path)
    end
  end

  def self.other_stub_file?(path)
    Gel::Environment.store.stub_set.parse_stub(path)
  end

  def self.flags(arguments)
    flag_constants = {
      "h" => Gel::Command::Help,
      "help" => Gel::Command::Help,
      "v" => Gel::Command::Version,
      "version" => Gel::Command::Version,
    }

    arguments.map { |word|
      match = word.match(/-+(?<flag>\w+)/)
      match && flag_constants[match[:flag]]
    }.compact
  end

  # If set to true, an error raised from #run will pass straight up to
  # ruby instead of being treated as an internal Gel error
  attr_accessor :reraise
end

require_relative "command/help"
require_relative "command/version"
require_relative "command/install"
require_relative "command/install_gem"
require_relative "command/env"
require_relative "command/exec"
require_relative "command/lock"
require_relative "command/update"
require_relative "command/ruby"
require_relative "command/stub"
require_relative "command/config"
require_relative "command/shell_setup"
require_relative "command/open"
require_relative "command/add"
