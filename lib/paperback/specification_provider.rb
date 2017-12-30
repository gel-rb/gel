# frozen_string_literal: true

require "molinillo"

class Paperback::SpecificationProvider
  include Molinillo::SpecificationProvider

  Spec = Struct.new(:name, :version) do
    def gem_version
      @gem_version ||= Paperback::Support::GemVersion.new(version.split("-", 2).first)
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
  end

  def initialize(catalogs)
    @catalogs = catalogs
  end

  def search_for(dependency)
    name = dependency.name

    result = []
    @catalogs.each do |catalog|
      if info = catalog.compact_index.gem_info(name)
        result += info.keys.select { |v| dependency.satisfied_by?(Spec.new(name, v)) }.map { |v| Spec.new(name, v) }
      end
    end
    result.sort_by { |spec| [spec.gem_version.prerelease? ? 0 : 1, spec.gem_version] }
  end

  def dependencies_for(specification)
    @catalogs.each do |catalog|
      info = catalog.compact_index.gem_info(specification.name)
      info &&= info[specification.version]
      return info[:dependencies].map { |n, cs| Dep.new(n, cs) } if info
    end
    []
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
        activated.vertex_named(name).payload ? 0 : 1,
        conflicts[name] ? 0 : 1,
      ]
    end
  end

  def allow_missing?(dependency)
    false
  end
end
