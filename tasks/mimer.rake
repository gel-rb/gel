# frozen_string_literal: true

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
