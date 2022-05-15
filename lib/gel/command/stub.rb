# frozen_string_literal: true

class Gel::Command::Stub < Gel::Command
  def run(command_line)
    # Note that the most common stub invocation doesn't actually pass
    # through here at all: a stubfile being run directly will present
    # as `gel <full-path-to-stubfile>` and will be handled by the
    # corresponding special case in the top level Gel::Command.run.
    #
    # We do get here when invoked by Gel.stub, or manual `gel stub foo`
    # execution, though. In both of those cases, the first element of
    # command_line will be the unqualified command to run, and the rest
    # will be its arguments -- so we can just pass command_line along to
    # Exec unmodified.
    #
    # However, there is one more situation that will end up here: when a
    # legacy stub file is invoked. In that case, after the unqualified
    # command name and before any supplied arguments, the shebang
    # invocation will have inserted the fully-qualified stubfile path as
    # well. We need to detect that, and strip it out.

    command_line.slice!(1) if redundant_stub_argument?(command_line)

    command = Gel::Command::Exec.new
    command.run(command_line, from_stub: true)
  ensure
    self.reraise = command.reraise if command
  end

  private

  def redundant_stub_argument?((command, possible_stub_path, *))
    return false unless possible_stub_path

    # Gel.stub injects a symbol to disambiguate the subsequent
    # arguments; we don't need to look any further, and definitely want
    # to strip it out.
    return true if possible_stub_path == :stub

    # A true redundant argument is a fully-qualified version of the
    # stubbed command. Does it even look like the names match?
    return false unless possible_stub_path.end_with?(command)

    # Okay, it seems plausible; in that case, it's time to check
    # properly.
    stub_set = Gel::Environment.store.stub_set
    stub_set.own_stub?(possible_stub_path) &&
      stub_set.parse_stub(possible_stub_path) == command
  end
end
