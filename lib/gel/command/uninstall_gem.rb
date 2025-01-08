# frozen_string_literal: true

class Gel::Command::UninstallGem < Gel::Command
  def run(command_line)
    gem_name, gem_version = command_line

    Gel::Environment.uninstall_gem(gem_name, gem_version, output: $stderr)
  end
end
