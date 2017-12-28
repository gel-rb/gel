# frozen_string_literal: true

require_relative "../paperback"

dir = ENV["PAPERBACK_STORE"] || "~/.local/paperback"
dir = File.expand_path(dir)

unless Dir.exist?(dir)
  require "fileutils"
  FileUtils.mkdir_p(dir)
end

dir = File.realpath(dir)

stores = {}
Paperback::Environment.store_set.each do |key|
  subdir = File.join(dir, key)
  Dir.mkdir(subdir) unless Dir.exist?(subdir)
  stores[key] = Paperback::Store.new(subdir)
end
store = Paperback::MultiStore.new(dir, stores)

Paperback::Environment::IGNORE_LIST.concat ENV["PAPERBACK_IGNORE"].split if ENV["PAPERBACK_IGNORE"]

Paperback::Environment.open(Paperback::LockedStore.new(store))

if ENV["PAPERBACK_LOCKFILE"]
  Paperback::Environment.activate(output: $stderr)
end

require_relative "compatibility"
