class Paperback::Command::Install < Paperback::Command
  def run(command_line)
    Paperback::Environment.load_gemfile

    lockfile = Paperback::Environment.gemfile.filename + ".lock"
    lockfile = nil unless File.exist?(lockfile)

    lockfile = ENV["PAPERBACK_LOCKFILE"] ||
      lockfile ||
      Paperback::Environment.search_upwards("Gemfile.lock") ||
      "Gemfile.lock"

    if File.exist?(lockfile)
      loader = Paperback::LockLoader.new(lockfile)

      loader.activate(Paperback::Environment, Paperback::Environment.store.inner, install: true, output: $stderr)
    else
      raise "No lockfile found in #{lockfile.inspect}"
    end
  end
end
