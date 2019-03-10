require "rake/testtask"

Rake::TestTask.class_eval do
  def rake_include_arg
    "-I\"#{rake_lib_dir}\""
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib/gel/compatibility"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

FIXTURE_GEMS = [
  ["rack", "2.0.3"],
  ["rack", "0.1.0"],
  ["hoe", "3.0.0"],
  ["rack-test", "0.6.3"],
  ["fast_blank", "1.0.0"],
  ["atomic", "1.1.16"],
  ["rainbow", "2.2.2"],
  ["rake", "12.3.2"],
]

task :fixtures do
  FIXTURE_GEMS.each do |name, version|
    filename = "test/fixtures/#{name}-#{version}.gem"
    next if File.exist?(filename)
    system "curl", "-s", "-o", filename, "https://rubygems.org/gems/#{name}-#{version}.gem"
  end
end

task :test => :fixtures

task :default => :test
