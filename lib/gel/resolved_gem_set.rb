# frozen_string_literal: true

require "set"

class Gel::ResolvedGemSet
  class ResolvedGem
    attr_reader :name, :version, :platform, :deps, :set

    def initialize(name, version, platform, deps, set:, catalog: nil)
      require_relative "catalog"

      @name = name
      @version = version
      @platform = platform
      @deps = deps

      @set = set
      @catalog = catalog
    end

    def catalog
      @catalog || set.catalog_for(self)
    end

    def full_version
      if platform
        "#{version}-#{platform}"
      else
        version
      end
    end
  end

  attr_reader :filename

  attr_writer :server_catalogs

  attr_accessor :catalog_uris
  attr_accessor :gems
  attr_accessor :platforms
  attr_accessor :ruby_version
  attr_accessor :bundler_version
  attr_accessor :dependencies

  def initialize(filename = nil)
    @filename = filename

    @gems = {}
  end

  def catalog_for(resolved_gem)
    # FIXME
  end

  def self.load(filename, git_depot: nil)
    result = new(filename)

    result.catalog_uris = Set.new

    Gel::LockParser.new.parse(File.read(filename)).each do |(section, body)|
      case section
      when "GEM", "PATH", "GIT"
        case section
        when "GEM"
          catalog = nil

          body["remote"]&.each do |remote|
            result.catalog_uris << remote
          end
        when "PATH"
          require_relative "path_catalog"
          catalog = Gel::PathCatalog.new(body["remote"].first)
        when "GIT"
          ref_type = [:branch, :tag, :ref].find { |t| body[t.to_s] } || :ref
          require_relative "git_catalog"
          catalog = Gel::GitCatalog.new(git_depot, body["remote"].first, ref_type, body[ref_type]&.first, body["revision"]&.first)
        end

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

          (result.gems[name] ||= []) << ResolvedGem.new(name, version, platform, deps, set: result, catalog: catalog)
        end
      when "PLATFORMS"
        result.platforms = body
      when "DEPENDENCIES"
        result.dependencies = body.map { |name| name.chomp("!") }
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

  def server_catalogs
    @server_catalogs ||= catalog_uris.map { |uri| Gel::Catalog.new(uri, work_pool: catalog_pool) }
  end

  def gem_names
    @gems.keys
  end

  def dependency_names
    dependencies&.map { |dep| dep.split(" ").first }
  end

  def dump
    lock_content = []

    output_specs_for = lambda do |results|
      lock_content << "  specs:"
      results.each do |resolved_gem|
        next if resolved_gem.name == "bundler" || resolved_gem.name == "ruby"

        lock_content << "    #{resolved_gem.name} (#{resolved_gem.full_version})"
        sorted_deps = resolved_gem.deps.sort_by { |dep_name, dep_reqs| dep_name }
        sorted_deps.each do |dep_name, dep_reqs|
          if dep_reqs
            lock_content << "      #{dep_name} (#{dep_reqs})"
          else
            lock_content << "      #{dep_name}"
          end
        end
      end
    end

    grouped_graph = gems.values.flatten(1).sort_by { |rg| [rg.name, "#{rg.full_version}"] }.group_by { |rg|
      catalog = rg.catalog
      catalog.is_a?(Gel::Catalog) || catalog.is_a?(Gel::StoreCatalog) ? nil : catalog
    }
    server_gems = grouped_graph.delete(nil)

    grouped_graph.keys.sort_by do |catalog|
      case catalog
      when Gel::GitCatalog
        [1, catalog.remote, catalog.revision]
      when Gel::PathCatalog
        [2, catalog.path]
      end
    end.each do |catalog|
      case catalog
      when Gel::GitCatalog
        lock_content << "GIT"
        lock_content << "  remote: #{catalog.remote}"
        lock_content << "  revision: #{catalog.revision}"
        lock_content << "  #{catalog.ref_type}: #{catalog.ref}" if catalog.ref
      when Gel::PathCatalog
        lock_content << "PATH"
        lock_content << "  remote: #{catalog.path}"
      end

      output_specs_for.call(grouped_graph[catalog])
      lock_content << ""
    end

    if server_gems
      lock_content << "GEM"
      server_catalogs.each do |catalog|
        lock_content << "  remote: #{catalog}"
      end
      output_specs_for.call(server_gems)
      lock_content << ""
    end

    if platforms && !platforms.empty?
      lock_content << "PLATFORMS"
      platforms.sort.each do |platform|
        lock_content << "  #{platform}"
      end
      lock_content << ""
    end

    lock_content << "DEPENDENCIES"
    non_bang_deps = server_gems&.map(&:name) || []
    dependencies.each do |dependency|
      dependency_name = dependency.split(" ").first
      bang = "!" unless non_bang_deps.include?(dependency_name)
      lock_content << "  #{dependency}#{bang}"
    end
    lock_content << ""

    if ruby_version
      lock_content << "RUBY VERSION"
      lock_content << "   #{ruby_version}"
      lock_content << ""
    end

    if bundler_version
      lock_content << "BUNDLED WITH"
      lock_content << "   #{bundler_version}"
      lock_content << ""
    end

    lock_content.join("\n")
  end

  private

  def catalog_pool
    require_relative "work_pool"
    @catalog_pool ||= Gel::WorkPool.new(8, name: "gel-catalog")
  end
end
