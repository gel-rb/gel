# frozen_string_literal: true

require "molinillo"

class Paperback::SpecificationProvider
  include Molinillo::SpecificationProvider

  Spec = Struct.new(:catalog, :name, :version, :info) do
    def gem_version
      @gem_version ||= Paperback::Support::GemVersion.new(version)
    end

    def to_s
      "#{name} #{version} #{info.inspect}"
    end
  end

  Dep = Struct.new(:name, :constraints) do
    def gem_requirement
      @gem_requirement ||= Paperback::Support::GemRequirement.new(constraints)
    end

    def satisfied_by?(spec)
      return false unless name == spec.name
      gem_requirement.satisfied_by?(spec.gem_version)
    end

    def to_s
      req_strings = gem_requirement.requirements.sort_by { |(_op, ver)| ver }.map { |(op, ver)| "#{op} #{ver}" }

      "#{name} (#{req_strings.join(", ")})"
    end
  end

  LateDep = Struct.new(:name, :blocks) do
    def dep
      Dep.new(name, constraints)
    end

    def constraints
      @constraints ||= blocks.flat_map(&:call)
    end

    def gem_requirement
      dep.gem_requirement
    end

    def satisfied_by?(spec)
      dep.satisfied_by?(spec)
    end
  end

  Ruby = Spec.new(nil, "ruby", RUBY_VERSION, [])

  def initialize(catalogs, active_platforms)
    @catalogs = catalogs
    @active_platforms = active_platforms

    @cached_specs = Hash.new { |h, k| h[k] = {} }
  end

  def search_for(dependency)
    name = dependency.name

    if name == "ruby"
      return dependency.satisfied_by?(Ruby) ? [Ruby] : []
    end

    result = []
    @catalogs.each do |catalog|
      if catalog.nil?
        break unless result.empty?
        next
      end

      if info = catalog.gem_info(name)
        @cached_specs[catalog][name] ||=
          begin
            grouped_versions = info.to_a.map do |full_version, attributes|
              version, platform = full_version.split("-", 2)
              platform ||= "ruby"
              [version, platform, attributes]
            end.group_by(&:first)

            grouped_versions.map { |version, tuples| Spec.new(catalog, name, version, tuples.map { |_, p, a| [p, a] }) }
          end

        result += @cached_specs[catalog][name].select { |spec| dependency.satisfied_by?(spec) }
      end
    end
    result.sort_by { |spec| [spec.gem_version.prerelease? ? 0 : 1, spec.gem_version] }
  end

  def dependencies_for(specification)
    info = specification.info
    info = info.select { |p, i| @active_platforms.include?(p) }

    deps = info.flat_map { |_, i| i[:dependencies] }.map { |n, cs| Dep.new(n, cs) }
    ruby_constraints = info.flat_map { |_, i| i[:ruby].is_a?(String) ? i[:ruby].split(/\s*,\s*/) : [] }
    unless ruby_constraints.empty?
      deps << Dep.new("ruby", ruby_constraints)
    end

    ruby_constraints = info.flat_map { |_, i| i[:ruby].is_a?(Proc) ? i[:ruby] : [] }
    unless ruby_constraints.empty?
      deps << LateDep.new("ruby", ruby_constraints)
    end

    deps
  end

  def requirement_satisfied_by?(requirement, activated, spec)
    requirement.satisfied_by?(spec)
  end

  def name_for(dependency)
    dependency.name
  end

  def name_for_explicit_dependency_source
    "user-specified dependency"
  end

  def name_for_locking_dependency_source
    "lockfile"
  end

  # Sort dependencies so that the ones that are easiest to resolve are first.
  # Easiest to resolve is (usually) defined by:
  #   1) Is this dependency already activated?
  #   2) How relaxed are the requirements?
  #   3) Are there any conflicts for this dependency?
  #   4) How many possibilities are there to satisfy this dependency?
  #
  # @param [Array<Object>] dependencies
  # @param [DependencyGraph] activated the current dependency graph in the
  #   resolution process.
  # @param [{String => Array<Conflict>}] conflicts
  # @return [Array<Object>] a sorted copy of `dependencies`.
  def sort_dependencies(dependencies, activated, conflicts)
    dependencies.sort_by do |dependency|
      name = name_for(dependency)
      [
        dependency.is_a?(LateDep) ? 1 : 0,
        activated.vertex_named(name).payload ? 0 : 1,
        conflicts[name] ? 0 : 1,
      ]
    end
  end

  def allow_missing?(dependency)
    false
  end
end
