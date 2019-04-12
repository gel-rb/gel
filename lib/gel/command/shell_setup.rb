# frozen_string_literal: true

class Gel::Command::ShellSetup < Gel::Command
  def run(command_line)
    require "shellwords"

    variables = []

    bin_dir = File.expand_path("~/.local/gel/bin")
    unless ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).include?(bin_dir)
      puts "PATH=\"#{Shellwords.shellescape bin_dir}#{File::PATH_SEPARATOR}$PATH\""
      variables << "PATH"
    end

    lib_dir = File.expand_path("../compatibility", __dir__)
    unless ENV.fetch("RUBYLIB", "").split(File::PATH_SEPARATOR).include?(lib_dir)
      puts "RUBYLIB=\"#{Shellwords.shellescape lib_dir}:$RUBYLIB\""
      variables << "RUBYLIB"
    end

    unless variables.empty?
      puts "export #{variables.join(" ")}"
    end
  end
end
