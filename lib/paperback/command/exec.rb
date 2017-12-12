class Paperback::Command::Exec < Paperback::Command
  def run(command_line)
    gemfile = Paperback::Environment.find_gemfile

    ENV["PAPERBACK_GEMFILE"] = File.expand_path(gemfile)
    ENV["PAPERBACK_LOCKFILE"] = File.expand_path(Paperback::Environment.lockfile_name(gemfile))

    opt = (ENV["RUBYOPT"] || "").split(" ")
    opt.unshift "-rpaperback/runtime" unless opt.include?("-rpaperback/runtime") || opt.each_cons(2).to_a.include?(["-r", "paperback/runtime"])
    opt.unshift "--disable=gems" unless opt.include?("--disable=gems") || opt.each_cons(2).to_a.include?(["--disable", "gems"])
    ENV["RUBYOPT"] = opt.join(" ")

    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    dir = File.expand_path("../..", __dir__)
    lib.unshift dir unless lib.include?(dir)
    ENV["RUBYLIB"] = lib.join(File::PATH_SEPARATOR)

    original_command = command_line.shift
    expanded_command = expand_executable(original_command)

    execute_inline(original_command, expanded_command, *command_line) || exec([original_command, expanded_command], *command_line)
  end

  def expand_executable(original_command)
    if original_command.include?(File::SEPARATOR) || (File::ALT_SEPARATOR && original_command.include?(File::ALT_SEPARATOR))
      return File.expand_path(original_command)
    end

    if Paperback::Environment.find_executable(original_command)
      Paperback::Environment.activate(output: $stderr)
      if found = Paperback::Environment.find_executable(original_command)
        return found
      end
    end

    path_attempts = ENV["PATH"].split(File::PATH_SEPARATOR).map { |e| File.join(e, original_command) }
    if found = path_attempts.find { |path| File.executable?(path) }
      return File.expand_path(found)
    end

    original_command
  end

  def execute_inline(original_command, expanded_command, *arguments)
    return unless File.exist?(expanded_command) && File.executable?(expanded_command)
    File.open(expanded_command, "rb") do |f|
      first_line = f.gets.chomp
      return unless first_line =~ /\A#!.*\bruby\b/
    end

    Paperback::Environment.activate(output: $stderr)
    $0 = original_command
    ARGV.replace(arguments)
    load expanded_command
    exit
  end
end
