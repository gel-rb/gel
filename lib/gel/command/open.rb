# frozen_string_literal: true

class Gel::Command::Open < Gel::Command
  def run(command_line)
    require "shellwords"

    raise "Please provide the name of a gem to open in your editor" if command_line.empty?
    raise "Too many arguments, only 1 gem name is supported" if command_line.length > 1
    gem_name = command_line.shift

    editor = ENV.fetch("GEL_EDITOR", ENV["EDITOR"])
    raise "An editor must be set using either $GEL_EDITOR or $EDITOR" unless editor

    Gel::Environment.activate(output: $stderr, error: false)

    found_gem = Gel::Environment.find_gem(gem_name)
    raise "Can't find gem `#{gem_name}`" unless found_gem

    command = [*Shellwords.split(editor), found_gem.root]
    Dir.chdir(found_gem.root) do
      exec(*command)
    end
  end
end
