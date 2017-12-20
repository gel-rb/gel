require_relative "lib/paperback"

case ARGV.shift
when "gemfile"
  Dir.chdir __dir__
  Dir.mkdir "tmp" unless Dir.exist?("tmp")
  Dir.mkdir "tmp/bootstrap" unless Dir.exist?("tmp/bootstrap")
  Dir.mkdir "tmp/bootstrap/store" unless Dir.exist?("tmp/bootstrap/store")
  Dir.mkdir "tmp/bootstrap/store/ruby" unless Dir.exist?("tmp/bootstrap/store/ruby")

  store = Paperback::Store.new("tmp/bootstrap/store/ruby")
  loader = Paperback::LockLoader.new("Gemfile.lock")

  loader.activate(nil, store, install: true, output: $stderr)

when "fetch"
  name, version = ARGV.shift, ARGV.shift

  cache_location = Paperback::Catalog.new("https://rubygems.org/").download_gem(name, version)
  require "fileutils"
  FileUtils.cp cache_location, "#{name}-#{version}.gem"

else
  raise "unknown"
end
