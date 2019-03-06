# frozen_string_literal: true

module Paperback::ReportableError
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
class Paperback::UserError < StandardError
  include Paperback::ReportableError

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

    while bt.last.path == ignored_bt.last.path
      bt.pop
    end

    bt
  end
end

module Paperback::Error
  class GemfileEvaluationError < Paperback::UserError
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
end
