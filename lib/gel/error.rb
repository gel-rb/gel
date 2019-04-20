# frozen_string_literal: true

module Gel::ReportableError
  # Include this module into any exception that should be treated as a
  # "user facing error" -- that means an error that's user _reportable_,
  # not necessarily that it's their fault.
  #
  # Examples of things that are user-facing errors:
  #   * unknown subcommand / arguments
  #   * requesting an unknown gem, or one with a malformed name
  #   * problems talking to a gem source
  #   * syntax errors inside a Gemfile or Gemfile.lock
  #   * dependency resolution failure
  #   * problems compiling or installing a gem
  #
  # In general, anything that's expected to possibly go wrong should at
  # some point be wrapped in a user error describing the problem in
  # terms of what they wanted to do. An unwrapped exception reaching the
  # top in Command#run is a bug: either the exception is itself
  # reporting a bug (nil reference, typo on a method name, etc), or if
  # it's a legitimate failure, then the bug is a missing rescue.

  def details
  end

  def exit_code
    1
  end
end

# Base class for user-facing errors. Errors _can_ directly include
# ReportableError to bypass this, but absent a specific reason, they
# should subclass UserError.
#
# Prefer narrow-purpose error classes that receive context parameters
# over raising generic classes with pre-rendered message parameters. The
# former can do a better job of fully describing the problem when
# producing detailed CLI output, without filling real code with long
# message heredocs.
#
# Define all UserError subclasses in this file. (Non-reportable errors,
# which describe errors in interaction between internal components, can
# and should be defined whereever they're used.)
class Gel::UserError < StandardError
  include Gel::ReportableError

  def initialize(**context)
    @context = context

    super message
  end

  def [](key)
    @context.fetch(key)
  end

  def message
    self.class.name
  end

  def inner_backtrace
    return [] unless cause

    bt = cause.backtrace_locations
    ignored_bt = backtrace_locations

    while bt.last.to_s == ignored_bt.last.to_s
      bt.pop
      ignored_bt.pop
    end

    bt.pop while bt.last.path == ignored_bt.last.path

    bt
  end
end

module Gel::Error
  class GemfileEvaluationError < Gel::UserError
    def initialize(filename:)
      super
    end

    def message
      "Failed to evaluate #{self[:filename].inspect}: #{cause&.message}"
    end

    def details
      inner_backtrace.join("\n")
    end
  end

  class BrokenStubError < Gel::UserError
    def initialize(name:)
      super
    end

    def message
      "No available gem supplies a #{self[:name].inspect} executable"
    end
  end

  class TooManyRedirectsError < Gel::UserError
    def initialize(original_uri:)
      super
    end

    def message
      "Too many redirects for #{self[:original_uri].inspect}"
    end
  end

  class UnknownCommandError < Gel::UserError
    def initialize(command_name:)
      super
    end

    def message
      "Unknown command #{self[:command_name].inspect}"
    end
  end

  class UnexpectedConfigError < Gel::UserError
    def initialize(line:)
      super
    end

    def message
      "Unexpected config line #{self[:line].inspect}"
    end
  end

  class CannotActivateError < Gel::UserError
    def initialize(path:, gemfile:)
      super
    end

    def message
      "Cannot activate #{self[:path].inspect}; already activated #{self[:gemfile].inspect}"
    end
  end

  class NoGemfile < Gel::UserError
    def initialzie(path:)
      super
    end

    def message
      "No Gemfile found in #{self[:path].inspect}"
    end
  end

  class NoVersionSatisfy < Gel::UserError
    def initialize(gem_name:, requirements:)
      super
    end

    def message
      "no version of gem #{self[:gem_name].inspect} satifies #{self[:requirements].inspect}"
    end
  end

  class UnknownGemError < Gel::UserError
    def initialize(gem_name:)
      super
    end

    def message
      "Unknown gem #{self[:gem_name].inspect}"
    end
  end

  class MismatchRubyVersionError < Gel::UserError
    def initialize(running:, requested:)
      super
    end

    def message
      "Running ruby version #{self[:running].inspect} does not match requested #{self[:requested].inspect}"
    end
  end

  class MismatchRubyEngineError < Gel::UserError
    def initialize(running:, engine:)
      super
    end

    def message
      "Running ruby engine #{self[:running].inspect} does not match requested #{self[:engine].inspect}"
    end
  end

  class ParsedGemspecError < Gel::UserError
    def message
      "Gemspec parse failed"
    end
  end
end
