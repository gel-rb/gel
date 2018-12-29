require "rake/testtask"

Rake::TestTask.class_eval do
  def rake_include_arg
    "-I\"#{rake_lib_dir}\""
  end
end

Rake::TestTask.new(:test) do |t|
  t.ruby_opts = ["--disable=gems", "-r", "paperback/runtime"]
  t.libs << "test"
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
]

task :fixtures do
  Dir.chdir "test/fixtures" do
    FIXTURE_GEMS.each do |name, version|
      filename = "#{name}-#{version}.gem"
      next if File.exist?(filename)
      system "curl", "-s", "-o", filename, "https://rubygems.org/gems/#{filename}"
    end
  end
end

task :test => :fixtures

task :default => :test
