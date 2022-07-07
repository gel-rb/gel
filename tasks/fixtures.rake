# frozen_string_literal: true

# These .gem files will be downloaded into test/fixtures/ before running
# tests, so they can be used either directly as files, or to simulate
# HTTP requests
FIXTURE_GEMS = [
  ["rack", "2.0.6"],
  ["rack", "2.0.3"],
  ["rack", "0.1.0"],
  ["hoe", "3.0.0"],
  ["rack-test", "0.6.3"],
  ["fast_blank", "1.0.0"],
  ["atomic", "1.1.16"],
  ["atomic", "1.1.16-java"],
  ["rainbow", "2.2.2"],
  ["rake", "12.3.2"],
  ["ruby_parser", "3.8.2"]
]

task :fixtures do
  FIXTURE_GEMS.each do |name, version|
    filename = "test/fixtures/#{name}-#{version}.gem"
    next if File.exist?(filename)
    system "curl", "-s", "-o", filename, "https://rubygems.org/gems/#{name}-#{version}.gem"
  end
end
