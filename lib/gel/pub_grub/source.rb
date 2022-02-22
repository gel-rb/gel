# frozen_string_literal: true

require_relative "../vendor/pub_grub"
require_relative "../../../vendor/pub_grub/lib/pub_grub/rubygems"

require_relative "package"
require_relative "../platform"

module Gel::PubGrub
  class Source < Gel::Vendor::PubGrub::BasicPackageSource
    attr_reader :root

    def initialize(gemfile, catalog_set, active_platforms, preference_strategy)
      @gemfile = gemfile
      @catalog_set = catalog_set
      @active_platforms = active_platforms
      @preference_strategy = preference_strategy

      # pub_grub-0.5.0/lib/pub_grub/basic_package_source.rb:165
      @packages = {}

      @root = Package::Pseudo.new(:root)

      super()
    end

    def active_platforms_map
      @active_platforms_map ||= Hash.new(@active_platforms).tap do |result|
        @gemfile.gems.each do |name, _, options|
          if options.key?(:platforms)
            filter = Array(options[:platforms] || ["ruby"]).map(&:to_s)
            result[name] = Gel::Platform.filter(@active_platforms, filter)
          end
        end
      end
    end

    def all_versions_for(package)
      if package.is_a?(Package::Pseudo)
        return [Gel::Support::GemVersion.new("0")]
      end

      @catalog_set.entries_for(package).map(&:gem_version)
    end

    def sort_versions_by_preferred(package, sorted_versions)
      sorted_versions = sorted_versions.reverse

      if @preference_strategy
        sorted_versions = @preference_strategy.sort_versions_by_preferred(package, sorted_versions)
      end

      prereleases, releases = sorted_versions.partition(&:prerelease?)
      releases.concat(prereleases)
    end

    def dependencies_for(package, version)
      deps = {}

      if package.is_a?(Package::Pseudo)
        case package.role
        when :root
          deps = { Package::Pseudo.new(:arguments) => [], Package::Pseudo.new(:gemfile) => [] }

        when :gemfile
          @gemfile.gems.each do |name, constraints, _|
            platforms = active_platforms_map[name]
            platforms = [nil] if platforms.empty?

            platforms.each do |platform|
              (deps[Package.new(name, platform)] ||= []).concat(constraints.flatten)
            end
          end

          deps.values.each(&:uniq!)

        when :arguments
          if @preference_strategy
            @preference_strategy.constraints.each do |name, constraints|
              @active_platforms.each do |platform|
                (deps[Package.new(name, platform)] ||= []).concat(constraints.flatten)
              end
            end
          end

        else
          raise "Unknown pseudo-package #{package.inspect}"
        end
      else
        @catalog_set.dependencies_for(package, version).each do |n, cs|
          (deps[Package.new(n, package.platform)] ||= []).concat(cs.flatten)
        end
      end

      deps
    end

    def parse_dependency(package, requirement)
      Gel::Vendor::PubGrub::VersionConstraint.new(package, range: to_range(requirement))
    end

    def incompatibilities_for(package, version)
      result = super

      unless package.is_a?(Package::Pseudo)
        other_platforms = @active_platforms - [package.platform]

        self_constraint = Gel::Vendor::PubGrub::VersionConstraint.new(package, range: Gel::Vendor::PubGrub::VersionRange.new(min: version, max: version, include_min: true, include_max: true))
        result += other_platforms.map do |other_platform|
          other_constraint = Gel::Vendor::PubGrub::VersionConstraint.new(Package.new(package.name, other_platform), range: Gel::Vendor::PubGrub::VersionUnion.new([Gel::Vendor::PubGrub::VersionRange.new(max: version), Gel::Vendor::PubGrub::VersionRange.new(min: version)]))
          Gel::Vendor::PubGrub::Incompatibility.new([Gel::Vendor::PubGrub::Term.new(self_constraint, true), Gel::Vendor::PubGrub::Term.new(other_constraint, true)], cause: :dependency)
        end
      end

      result
    end

    private

    def to_range(constraints)
      requirement = Gel::Support::GemRequirement.new(constraints)
      Gel::Vendor::PubGrub::RubyGems.requirement_to_range(requirement)
    end
  end
end
