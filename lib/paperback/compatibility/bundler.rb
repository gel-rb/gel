module Bundler
  def self.setup
    Paperback::Environment.load_gemfile

    lockfile = Paperback::Environment.gemfile.filename + ".lock"
    lockfile = nil unless File.exist?(lockfile)

    lockfile = ENV["PAPERBACK_LOCKFILE"] ||
      lockfile ||
      Paperback::Environment.search_upwards("Gemfile.lock") ||
      "Gemfile.lock"

    if File.exist?(lockfile)
      loader = Paperback::LockLoader.new(lockfile)

      loader.activate(Paperback::Environment, Paperback::Environment.store.inner, install: !!ENV["PAPERBACK_INSTALL"], output: $stderr)
    else
      raise "No lockfile found in #{lockfile.inspect}"
    end
  end

  def self.require(*groups)
    Paperback::Environment.require_groups(*groups)
  end
end
