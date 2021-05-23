require "rake/testtask"
require "shellwords"

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
  ["pub_grub", "0.5.0"],
  ["ruby_parser", "3.8.2"]
]

# These gems specify the subset of the entire gemspace that is simulated
# by the Gem Mimer fixture helper, used in resolver tests. All versions,
# and all dependencies of all versions, recursively, are known to exist.
#
# The output of this task is text, and harder to automatically cache, so
# it gets committed as test/fixtures/index/{info.rb,versions}. After
# changing this list, run `rake mimer` to regenerate and then commit the
# result.
MIMED_GEMS = [
  "pub_grub",

  "activerecord-jdbcpostgresql-adapter",
  "activerecord-jdbcsqlite3-adapter",
  "foreman",
  "gruff",
  "pg",
  "quiet_assets",
  "rails",
  "rspec-rails",
  "sqlite3",
  "tzinfo-data",
]

task :fixtures do
  FIXTURE_GEMS.each do |name, version|
    filename = "test/fixtures/#{name}-#{version}.gem"
    next if File.exist?(filename)
    system "curl", "-s", "-o", filename, "https://rubygems.org/gems/#{name}-#{version}.gem"
  end
end

task :mimer do
  require "net/http"
  require "set"

  all_gems = Set.new(MIMED_GEMS)
  pending_gems = MIMED_GEMS.dup

  gem_infos = {}

  until pending_gems.empty?
    name = pending_gems.shift
    puts "#{name} (#{gem_infos.size} / #{all_gems.size})"

    info = Net::HTTP.get(URI("https://index.rubygems.org/info/#{name}"))
    gem_infos[name] = info

    info.each_line do |line|
      line.chop!
      next if line == "---"
      _version, rest = line.split(" ", 2)
      deps, _extra = rest.split("|", 2)
      deps = deps.split(",")
      deps.each do |dep_string|
        dep_name, _versions = dep_string.split(":", 2)
        pending_gems << dep_name if all_gems.add?(dep_name)
      end
    end
  end

  regex = /\A#{Regexp.union(all_gems.to_a)} /

  puts "Downloading versions"
  versions = Net::HTTP.get(URI("https://rubygems.org/versions"))

  known_versions = Hash.new { |h, k| h[k] = [] }

  puts "Writing versions"
  File.open("test/fixtures/index/versions", "w") do |f|
    header = true
    cutoff = false
    versions.each_line do |line|
      if header
        f.write(line)
        header = false if line == "---\n"
        next
      end

      if line == "dependabot-omnibus 0.86.21 32213ec6b8685f939aec10e2b413f6af\n"
        # point-in-time cutoff: nothing after this line exists, except
        # our own dependencies
        cutoff = true
      end

      if cutoff ? line.start_with?("pub_grub ") : line.match?(regex)
        f.write(line)
        gem_name, versions, _ = line.split(" ")
        known_versions[gem_name] |= versions.split(",").each { |v| v.sub!(/^-/, "") }
      end
    end
  end

  puts "Writing info.rb"
  File.open("test/fixtures/index/info.rb", "w") do |f|
    f.puts <<~RUBY
      # frozen_string_literal: true

      FIXTURE_INDEX = {
    RUBY

    all_gems.to_a.sort.each do |gem_name|
      info_lines = gem_infos[gem_name].lines

      f.puts %(  #{gem_name.inspect} => <<INFO,)
      f.puts info_lines.shift # "---"
      info_lines.each do |line|
        version, _ = line.split(" ", 2)
        version = version[1..-1] if version.start_with?("-")
        f.puts line if known_versions[gem_name].include?(version)
      end
      f.puts "INFO"
    end

    f.puts "}"
  end

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
