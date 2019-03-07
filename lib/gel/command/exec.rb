# frozen_string_literal: true

class Gel::Command::Exec < Gel::Command
  def run(command_line)
    gemfile = Gel::Environment.find_gemfile

    ENV["GEL_GEMFILE"] = File.expand_path(gemfile)
    ENV["GEL_LOCKFILE"] = File.expand_path(Gel::Environment.lockfile_name(gemfile))

    opt = (ENV["RUBYOPT"] || "").split(" ")
    opt.unshift "-rgel/runtime" unless opt.include?("-rgel/runtime") || opt.each_cons(2).to_a.include?(["-r", "gel/runtime"])
    opt.unshift "--disable=gems" unless opt.include?("--disable=gems") || opt.each_cons(2).to_a.include?(["--disable", "gems"])
    ENV["RUBYOPT"] = opt.join(" ")

    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    dir = File.expand_path("../..", __dir__)
    lib.unshift dir unless lib.include?(dir)
    ENV["RUBYLIB"] = lib.join(File::PATH_SEPARATOR)

    original_command = command_line.shift
    expanded_command = expand_executable(original_command)

    if execute_inline?(expanded_command)
      Gel::Environment.activate(output: $stderr)
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
      return File.expand_path(original_command)
    end

    if Gel::Environment.find_executable(original_command)
      Gel::Environment.activate(output: $stderr)
      if found = Gel::Environment.find_executable(original_command)
        return found
      end
    end

    path_attempts = ENV["PATH"].split(File::PATH_SEPARATOR).map { |e| File.join(e, original_command) }
    if found = path_attempts.find { |path| File.executable?(path) }
      return File.expand_path(found)
    end

    original_command
  end

  def execute_inline?(expanded_command)
    if File.exist?(expanded_command) && File.executable?(expanded_command)
      File.open(expanded_command, "rb") do |f|
        f.read(2) == "#!" && f.gets.chomp =~ /\bruby\b/
      end
    end
  end
end
