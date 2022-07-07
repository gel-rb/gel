require "rake/testtask"
require "shellwords"

Dir["#{__dir__}/tasks/*.rake"].sort.each { |file| load file }

Rake::TestTask.class_eval do
  def rake_include_arg
    "-I\"#{rake_lib_dir}\""
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "slib"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = RUBY_VERSION >= "3"
end

task test: :fixtures

MAN_SOURCES = Rake::FileList.new("man/*/*.ronn")
MAN_PAGES = MAN_SOURCES.map { |source| source.delete(".ronn") }

file MAN_PAGES => :man

task :man => MAN_SOURCES do
  sh "ronn --roff --manual 'Gel Manual' #{Shellwords.shelljoin MAN_SOURCES}"
end

task build: :man do
  Dir.mkdir "pkg" unless Dir.exist?("pkg")

  File.read(File.expand_path("lib/gel/version.rb", __dir__)) =~ /VERSION.*\"(.*)\"/
  version = $1
  sh "gem build -o pkg/gel-#{version}.gem gel.gemspec"
end

task default: :test
