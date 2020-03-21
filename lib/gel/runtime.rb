# frozen_string_literal: true

require_relative "../gel"

dir = ENV["GEL_STORE"] || "~/.local/gel"
dir = File.expand_path(dir)

unless Dir.exist?(dir)
  require "fileutils"
  FileUtils.mkdir_p(dir)
end

dir = File.realpath(dir)

stores = {}
Gel::Environment.store_set.each do |key|
  subdir = File.join(dir, key)
  Dir.mkdir(subdir) unless Dir.exist?(subdir)
  stores[key] = Gel::Store.new(subdir)
end
store = Gel::MultiStore.new(dir, stores)

Gel::Environment.open(Gel::LockedStore.new(store))

if ENV["GEL_LOCKFILE"] && ENV["GEL_LOCKFILE"] != ""
  Gel::Environment.activate(output: $stderr)
end
