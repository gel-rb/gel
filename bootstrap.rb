require "paperback"

case ARGV.shift
when "gemfile"
  Dir.chdir __dir__
  Dir.mkdir "tmp" unless Dir.exist?("tmp")
  Dir.mkdir "tmp/bootstrap" unless Dir.exist?("tmp/bootstrap")
  Dir.mkdir "tmp/bootstrap/store" unless Dir.exist?("tmp/bootstrap/store")

  store = Paperback::Store.new("tmp/bootstrap/store")
  loader = Paperback::LockLoader.new("Gemfile.lock")

  loader.activate(nil, store, install: true)

when "fetch"
  name, version = ARGV.shift, ARGV.shift

  temp = Paperback::Catalog.new("https://rubygems.org/").download_gem(name, version)
  File.open("#{name}-#{version}.gem", "wb") do |f|
    f.write(temp.read)
  end

else
  raise "unknown"
end
