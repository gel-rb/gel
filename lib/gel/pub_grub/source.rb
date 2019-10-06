# frozen_string_literal: true

require "pub_grub"
require "pub_grub/basic_package_source"
require "pub_grub/rubygems"

module Gel::PubGrub
  class Source < ::PubGrub::BasicPackageSource
    attr_reader :root, :root_version

    def initialize(gemfile, catalog_set, active_platforms, preference_strategy)
      @gemfile = gemfile
      @catalog_set = catalog_set
      @active_platforms = active_platforms
      @preference_strategy = preference_strategy

      @packages = Hash.new {|h, k| h[k] = PubGrub::Package.new(k) }
      @root = PubGrub::Package.root
      @root_version = PubGrub::Package.root_version

      super()
    end

    def all_versions_for(package)
      if package.name =~ /^~/
        return [Gem::Version.new("0")]
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

      case package.name
      when "~arguments"
        if @preference_strategy
          @preference_strategy.constraints.each do |name, constraints|
            deps[name] ||= []
            deps[name].concat constraints.flatten
          end
        end
      when /^~/
        raise "Unknown pseudo-package"
      else
        @catalog_set.dependencies_for(package, version, platforms: @active_platforms).each do |n, cs|
          deps[n] ||= []
          deps[n].concat cs
        end
      end

      deps
    end

    def root_dependencies
      deps = { "~arguments" => [] }

      @gemfile.gems_for_platforms([:ruby, :mri]).each do |name, constraints, _|
        deps[name] ||= []
        deps[name].concat constraints.flatten
      end

      deps.values.each(&:uniq!)

      deps
    end

    def parse_dependency(package, requirement)
      ::PubGrub::VersionConstraint.new(@packages[package], range: to_range(requirement))
    end

    private

    def to_range(constraints)
      requirement = Gel::Support::GemRequirement.new(constraints)
      ::PubGrub::RubyGems.requirement_to_range(requirement)
    end
  end
end
