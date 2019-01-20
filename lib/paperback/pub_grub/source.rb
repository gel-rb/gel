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

      def available_platforms
        info.map(&:first)
      end

      def available_on_platforms?(requested_platforms)
        requested_platforms.all? do |requested_platform|
          Paperback::Platform.match(requested_platform, available_platforms)
        end
      end

      def active_platforms(requested_platforms)
        requested_platforms.map do |requested_platform|
          Paperback::Platform.match(requested_platform, available_platforms)
        end.uniq
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

      if package.name =~ /(.*)@(.*)/
        package = @packages[$1]
      end

      @specs_by_package_version[package][version.to_s]
    end

    def all_versions_for(package)
      if package.name =~ /^~/
        return [Gem::Version.new("0")]
      end

      if package.name =~ /(.*)@(.*)/
        package_name, platform = $1, $2
        package = @packages[package_name]
      end

      fetch_package_info(package)

      @specs_by_package_version[package].values.
        select { |spec| spec.available_on_platforms?(platform ? [platform] : @active_platforms[package.name]) }.
        map(&:gem_version)
    end

    def sort_versions_by_preferred(package, sorted_versions)
      if package.name =~ /(.*)@(.*)/
        package = @packages[$1]
      end

      sorted_versions = sorted_versions.reverse

      if @preference_strategy
        sorted_versions = @preference_strategy.sort_versions_by_preferred(package, sorted_versions)
      end

      prereleases, releases = sorted_versions.partition(&:prerelease?)
      releases.concat(prereleases)
    end

    def dependencies_for(package, version, platform = nil)
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
      when /(.*)@(.*)/
        return dependencies_for(@packages[$1], version, $2)
      else
        fetch_package_info(package) # probably already done, can't hurt

        spec = @specs_by_package_version[package][version.to_s]
        info = spec.info
        if platform
          release_platform = Paperback::Platform.match(platform, spec.available_platforms)
          info = info.select { |p, i| p == release_platform }
        end

        info.flat_map { |_, i| i[:dependencies] }.each do |n, cs|
          n += "@#{platform}" if platform
          deps[n] ||= []
          deps[n].concat cs
        end

        # FIXME: ruby_constraints ???
      end

      deps
    end

    def root_dependencies
      deps = { "~arguments" => [] }

      @gemfile.gems.each do |name, constraints, _|
        @active_platforms[name].each do |platform|
          deps["#{name}@#{platform}"] ||= []
          deps["#{name}@#{platform}"].concat constraints.flatten
        end
      end

      deps.values.each(&:uniq!)

      deps
    end

    def parse_dependency(package, requirement)
      ::PubGrub::VersionConstraint.new(@packages[package], range: to_range(requirement))
    end

    def incompatibilities_for(package, version)
      result = super

      if package.name =~ /(.*)@(.*)/
        this_platform = $2
        package_name = $1

        other_platforms = @active_platforms[nil] - [this_platform]

        self_constraint = PubGrub::VersionConstraint.new(package, range: PubGrub::VersionRange.new(min: version, max: version, include_min: true, include_max: true))
        result += other_platforms.map do |other_platform|
          other_constraint = PubGrub::VersionConstraint.new(@packages["#{package_name}@#{other_platform}"], range: PubGrub::VersionUnion.new([PubGrub::VersionRange.new(max: version), PubGrub::VersionRange.new(min: version)]))
          PubGrub::Incompatibility.new([PubGrub::Term.new(self_constraint, true), PubGrub::Term.new(other_constraint, true)], cause: :dependency)
        end
      end

      result
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
