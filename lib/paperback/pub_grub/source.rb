# frozen_string_literal: true

require "pub_grub"
require "pub_grub/basic_package_source"
require "pub_grub/rubygems"

module Paperback::PubGrub
  class Source < ::PubGrub::BasicPackageSource
    Spec = Struct.new(:catalog, :name, :version, :info) do
      def gem_version
        @gem_version ||= Paperback::Support::GemVersion.new(version)
      end
    end

    attr_reader :root, :root_version

    def initialize(gemfile, catalogs, active_platforms, preference_strategy)
      @gemfile = gemfile
      @catalogs = catalogs
      @active_platforms = active_platforms
      @preference_strategy = preference_strategy

      @packages = Hash.new {|h, k| h[k] = PubGrub::Package.new(k) }
      @root = PubGrub::Package.root
      @root_version = PubGrub::Package.root_version

      @cached_specs = Hash.new { |h, k| h[k] = {} }
      @specs_by_package_version = {}

      super()
    end

    def spec_for_version(package, version)
      if package.name =~ /^~/
        return Spec.new(nil, package.name, version, [])
      end

      @specs_by_package_version[package][version.to_s]
    end

    def all_versions_for(package)
      if package.name =~ /^~/
        return [Gem::Version.new("0")]
      end

      fetch_package_info(package)

      @specs_by_package_version[package].values.map(&:gem_version)
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
        fetch_package_info(package) # probably already done, can't hurt

        spec = @specs_by_package_version[package][version.to_s]
        info = spec.info
        info = info.select { |p, i| @active_platforms.include?(p) }

        info.flat_map { |_, i| i[:dependencies] }.each do |n, cs|
          deps[n] ||= []
          deps[n].concat cs
        end

        # FIXME: ruby_constraints ???
      end

      deps
    end

    def root_dependencies
      deps = { "~arguments" => [] }

      @gemfile.gems.select do |_, _, options|
        next true unless platforms = options[:platforms]
        !([*platforms] & [:ruby, :mri]).empty?
      end.each do |name, constraints, _|
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

    def fetch_package_info(package)
      return if @specs_by_package_version.key?(package)

      specs = []
      @catalogs.each do |catalog|
        if catalog.nil?
          break unless specs.empty?
          next
        end

        if info = catalog.gem_info(package.name)
          @cached_specs[catalog][package.name] ||=
            begin
              grouped_versions = info.to_a.map do |full_version, attributes|
                version, platform = full_version.split("-", 2)
                platform ||= "ruby"
                [version, platform, attributes]
              end.group_by(&:first)

              grouped_versions.map { |version, tuples| Spec.new(catalog, package.name, version, tuples.map { |_, p, a| [p, a] }) }
            end

          specs.concat @cached_specs[catalog][package.name]
        end
      end

      @specs_by_package_version[package] = {}
      specs.each do |spec|
        # TODO: are we going to find specs in multiple catalogs this way?
        @specs_by_package_version[package][spec.version] = spec
      end
    end

    def to_range(constraints)
      requirement = Paperback::Support::GemRequirement.new(constraints)
      ::PubGrub::RubyGems.requirement_to_range(requirement)
    end
  end
end
