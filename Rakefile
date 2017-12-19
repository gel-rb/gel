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

[
  ["rack", "2.0.3"],
  ["rack", "0.1.0"],
  ["hoe", "3.0.0"],
  ["rack-test", "0.6.3"],
  ["fast_blank", "1.0.0"],
  ["atomic", "1.1.16"],
].each do |name, version|
  file "test/fixtures/#{name}-#{version}.gem" do
    Dir.chdir "test/fixtures" do
      system "../../bin/paperruby", "../../bootstrap.rb", "fetch", name, version
    end
  end

  task :fixtures => "test/fixtures/#{name}-#{version}.gem"
end

task :test => :fixtures

task :default => :test
