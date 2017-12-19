# TODO: This loads too much
require_relative "../paperback"

require "rbconfig"
dir = ENV["PAPERBACK_STORE"] || "~/.local/paperback"
dir = File.expand_path(dir)

require "fileutils"
FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

stores = {}
Paperback::Environment.store_set.each do |key|
  subdir = File.join(dir, key)
  FileUtils.mkdir_p(subdir) unless Dir.exist?(subdir)
  stores[key] = Paperback::Store.new(subdir)
end
store = Paperback::MultiStore.new(stores)

Paperback::Environment::IGNORE_LIST.concat ENV["PAPERBACK_IGNORE"].split if ENV["PAPERBACK_IGNORE"]

Paperback::Environment.open(Paperback::LockedStore.new(store))

if ENV["PAPERBACK_LOCKFILE"]
  Paperback::Environment.activate(output: $stderr)
end

require_relative "compatibility"
