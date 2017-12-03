unless lockfile = ENV["PAPERBACK_LOCKFILE"]
  lockfile = "Gemfile.lock"
  while lockfile && !File.exist?(lockfile)
    new_lockfile = File.expand_path("../../Gemfile.lock", lockfile)
    lockfile = new_lockfile == lockfile ? nil : new_lockfile
  end
  lockfile ||= "Gemfile.lock"
end

if File.exist?(lockfile)
  loader = Paperback::LockLoader.new(lockfile)

  loader.activate(Paperback::Environment, Paperback::Environment.store.inner, install: !!ENV["PAPERBACK_INSTALL"], output: $stderr)
else
  raise "No lockfile found in #{lockfile.inspect}"
end
