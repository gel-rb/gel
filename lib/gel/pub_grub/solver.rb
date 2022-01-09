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
      versions = self.source.versions_for(package, term.constraint.range)

      if @strategy
        @strategy.package_priority(package, versions) + @package_depth[package]
      else
        @package_depth[package]
      end * 1000 + versions.count
    end.package
  end

  def each_resolved_package(&block)
    result.each do |package, version|
      next if package.is_a?(Gel::PubGrub::Package::Pseudo)
      yield package, version
    end
  end
end
