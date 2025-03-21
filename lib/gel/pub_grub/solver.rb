# frozen_string_literal: true

require_relative "source"

class Gel::PubGrub::Solver < Gel::Vendor::PubGrub::VersionSolver
  def self.logger
    ::Gel::Vendor::PubGrub.logger
  end

  def initialize(gemfile:, catalog_set:, platforms:, strategy:)
    source = Gel::PubGrub::Source.new(gemfile, catalog_set, platforms, strategy)

    super(source: source, root: source.root)

    @strategy = strategy
  end

  def next_package_to_try
    self.solution.unsatisfied.min_by do |term|
      package = term.package
      range = term.constraint.range
      matching_versions = source.versions_for(package, range)
      higher_versions = source.versions_for(package, range.upper_invert)

      matching_priority = matching_versions.count <= 1 ? 0 : 1

      if @strategy
        [@strategy.package_priority(package, matching_versions), matching_priority, higher_versions.count]
      else
        [matching_priority, higher_versions.count]
      end
    end.package
  end

  def each_resolved_package(&block)
    result.each do |package, version|
      next if package.is_a?(Gel::PubGrub::Package::Pseudo)
      yield package, version
    end
  end
end
