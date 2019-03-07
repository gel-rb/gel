# frozen_string_literal: true

require_relative "lib/gel"

def usage
  puts "USAGE: ruby bootstrap.rb gemfile"
  exit 1
end

case ARGV.shift
when "gemfile"
  usage unless ARGV.length == 0

  Dir.chdir __dir__
  Dir.mkdir "tmp" unless Dir.exist?("tmp")
  Dir.mkdir "tmp/bootstrap" unless Dir.exist?("tmp/bootstrap")
  Dir.mkdir "tmp/bootstrap/store" unless Dir.exist?("tmp/bootstrap/store")
  Dir.mkdir "tmp/bootstrap/store/ruby" unless Dir.exist?("tmp/bootstrap/store/ruby")

  store = Gel::Store.new("tmp/bootstrap/store/ruby")
  loader = Gel::LockLoader.new("Gemfile.lock")

  loader.activate(nil, store, install: true, output: $stderr)

else
  usage
end
