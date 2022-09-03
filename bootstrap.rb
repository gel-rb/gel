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

  # `gel install`
  loader = Gel::LockLoader.new(Gel::ResolvedGemSet.load("Gemfile.lock"), Gel::GemfileParser.parse(File.read("Gemfile"), "Gemfile", 1))
  loader.activate(Gel::Environment, Gel::Environment.root_store, install: true, output: $stderr)

else
  usage
end
