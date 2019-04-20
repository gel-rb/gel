# frozen_string_literal: true

class Gel::Command::Exec < Gel::Command
  def run(command_line, from_stub: false)
    original_command = command_line.shift
    expanded_command, command_source = expand_executable(original_command)

    if from_stub && [:original, :path].include?(command_source)
      raise Gel::Error::BrokenStubError.new(name: original_command)
    end

    gemfile = Gel::Environment.find_gemfile(error: false)

    if gemfile && command_source != :gem
      ENV["GEL_GEMFILE"] = File.expand_path(gemfile)
      ENV["GEL_LOCKFILE"] = File.expand_path(Gel::Environment.lockfile_name(gemfile))
    end

    ENV["RUBYLIB"] = Gel::Environment.modified_rubylib

    if execute_inline?(expanded_command)
      if command_source == :path || command_source == :original
        if ENV["GEL_LOCKFILE"]
          Gel::Environment.activate(output: $stderr)
        end
      end

      $0 = original_command
      ARGV.replace(command_line)

      # Any error after this point should bypass Gel's error
      # handling
      self.reraise = true
      Kernel.load(expanded_command)
    else
      Kernel.exec([original_command, expanded_command], *command_line)
    end
  end

  def expand_executable(original_command)
    if original_command.include?(File::SEPARATOR) || (File::ALT_SEPARATOR && original_command.include?(File::ALT_SEPARATOR))
      return [File.expand_path(original_command), :path]
    end

    if (source = Gel::Environment.activate_for_executable([original_command]))
      if (found = Gel::Environment.find_executable(original_command))
        return [found, source]
      end
    end

    path_attempts = ENV["PATH"].split(File::PATH_SEPARATOR).map { |e| File.join(e, original_command) }
    if (found = path_attempts.find { |path| File.executable?(path) })
      return [File.expand_path(found), :path]
    end

    [original_command, :original]
  end

  def execute_inline?(expanded_command)
    if File.exist?(expanded_command) && File.executable?(expanded_command)
      File.open(expanded_command, "rb") do |f|
        f.read(2) == "#!" && f.gets.chomp =~ /\bruby\b/
      end
    end
  end
end
