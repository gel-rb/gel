# TODO: This loads too much
require_relative "../paperback"

require "rbconfig"
dir = ENV["PAPERBACK_STORE"] || "~/.local/paperback/#{RbConfig::CONFIG["ruby_version"]}"
dir = File.expand_path(dir)

require "fileutils"
FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
store = Paperback::Store.new(dir)

Paperback::Environment::IGNORE_LIST.concat ENV["PAPERBACK_IGNORE"].split if ENV["PAPERBACK_IGNORE"]

Paperback::Environment.open(Paperback::LockedStore.new(store))

if ENV["PAPERBACK_LOCKFILE"]
  Paperback::Environment.activate(output: $stderr)
end

require_relative "compatibility"
