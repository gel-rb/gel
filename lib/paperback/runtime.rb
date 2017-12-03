# TODO: This loads too much
require "paperback"

require "rbconfig"
dir = ENV["PAPERBACK_STORE"] || "~/.local/paperback/#{RbConfig::CONFIG["ruby_version"]}"
dir = File.expand_path(dir)

require "fileutils"
FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
store = Paperback::Store.new(dir)

if ENV["PAPERBACK_LOCKFILE"]
  Paperback::Environment::IGNORE_LIST.concat ENV["PAPERBACK_IGNORE"].split if ENV["PAPERBACK_IGNORE"]

  loader = Paperback::LockLoader.new(ENV["PAPERBACK_LOCKFILE"])

  loader.activate(Paperback::Environment, store, install: !!ENV["PAPERBACK_INSTALL"], output: $stderr)
else
  Paperback::Environment.activate(Paperback::LockedStore.new(store))
end

require "paperback/compatibility"
