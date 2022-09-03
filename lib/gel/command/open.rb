# frozen_string_literal: true

class Gel::Command::Open < Gel::Command
  def run(command_line)
    require "shellwords"

    raise "Please provide the name of a gem to open in your editor" if command_line.empty?

    gem_name = command_line.shift

    if command_line.first == "-v"
      command_line.shift
      version = command_line.shift
    end

    raise "Too many arguments, only one gem name is supported" if command_line.length > 0

    editor = ENV.fetch("GEL_EDITOR", ENV["EDITOR"])
    raise "An editor must be set using either $GEL_EDITOR or $EDITOR" unless editor

    Gel::Environment.activate(output: $stderr, error: false)

    found_gem = Gel::Environment.find_gem(gem_name, version)
    unless found_gem
      raise Gel::Error::UnsatisfiedDependencyError.new(
        name: gem_name,
        was_locked: Gel::Environment.locked?,
        found_any: Gel::Environment.find_gem(gem_name),
        requirements: Gel::Support::GemRequirement.new(version),
        why: nil,
      )
    end

    command = [*Shellwords.split(editor), found_gem.root]
    Dir.chdir(found_gem.root) do
      exec(*command)
    end
  end
end
