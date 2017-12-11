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

    execute_inline(*command_line) || exec(*command_line)
  end

  def execute_inline(file, *arguments)
    return unless File.exist?(file) && File.executable?(file)
    File.open(file, "rb") do |f|
      first_line = f.gets.chomp
      return unless first_line =~ /\A#!.*\bruby\b/
    end

    Paperback::Environment.activate(output: $stderr)
    $0 = file
    ARGV.replace(arguments)
    load $0
    exit
  end
end
