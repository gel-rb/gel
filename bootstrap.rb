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

  # `gel install-gem pub_grub`
  require_relative "lib/gel/catalog"
  require_relative "lib/gel/work_pool"
  Gel::WorkPool.new(2) do |work_pool|
    catalog = Gel::Catalog.new("https://rubygems.org", work_pool: work_pool)

    Gel::Environment.install_gem([catalog], "pub_grub", nil, output: $stderr)
  end

  # `gel install`
  loader = Gel::LockLoader.new("Gemfile.lock")
  loader.activate(nil, Gel::Environment.store.inner, install: true, output: $stderr)

else
  usage
end
