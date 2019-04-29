# frozen_string_literal: true

class Gel::ResolvedGemSet
  class ResolvedGem < Struct.new(:type, :body, :name, :version, :platform, :deps)
  end

  attr_reader :filename

  attr_accessor :gems
  attr_accessor :platforms
  attr_accessor :ruby_version
  attr_accessor :bundler_version
  attr_accessor :dependencies

  def initialize(filename = nil)
    @filename = filename

    @gems = {}
  end

  def self.load(filename)
    result = new(filename)

    Gel::LockParser.new.parse(File.read(filename)).each do |(section, body)|
      case section
      when "GEM", "PATH", "GIT"
        specs = body["specs"]
        specs.each do |gem_spec, dep_specs|
          gem_spec =~ /\A(.+) \(([^-]+)(?:-(.+))?\)\z/
          name, version, platform = $1, $2, $3

          if dep_specs
            deps = dep_specs.map do |spec|
              spec =~ /\A(.+?)(?: \((.+)\))?\z/
              [$1, $2 ? $2.split(", ") : []]
            end
          else
            deps = []
          end

          sym =
            case section
            when "GEM"; :gem
            when "PATH"; :path
            when "GIT"; :git
            end
          (result.gems[name] ||= []) << ResolvedGem.new(sym, body, name, version, platform, deps)
        end
      when "PLATFORMS"
        result.platforms = body
      when "DEPENDENCIES"
        result.dependencies = body.map { |name| name.split(" ", 2)[0].chomp("!") }
      when "RUBY VERSION"
        result.ruby_version = body.first
      when "BUNDLED WITH"
        result.bundler_version = body.first
      else
        warn "Unknown lockfile section #{section.inspect}"
      end
    end

    result
  end

  def gem_names
    @gems.keys
  end
end
