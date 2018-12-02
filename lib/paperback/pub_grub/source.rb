# frozen_string_literal: true

require "pub_grub"

module Paperback::PubGrub
  class Source
    Spec = Struct.new(:name, :version, :info) do
      def gem_version
        @gem_version ||= Paperback::Support::GemVersion.new(version)
      end
    end

    attr_reader :root, :root_version

    def initialize(gemfile, catalogs, active_platforms)
      @gemfile = gemfile
      @catalogs = catalogs
      @active_platforms = active_platforms

      @packages = Hash.new {|h, k| h[k] = PubGrub::Package.new(k) }
      @root = PubGrub::Package.root
      @root_version = PubGrub::Package.root_version

      @cached_specs = Hash.new { |h, k| h[k] = {} }
      @specs_by_package_version = {}
    end

    def versions_for(package, range=PubGrub::VersionRange.any)
      return [@root_version] if package == @root

      fetch_package_info(package)

      @specs_by_package_version[package].
        values.
        map(&:gem_version).
        select { |version| range.include?(version) }.
        sort_by { |version| [version.prerelease? ? 0 : 1, version] }.
        reverse
    end

    def dependencies_for(package, version)
      if package == @root
        root_deps
      else
        fetch_package_info(package) # probably already done, can't hurt

        spec = @specs_by_package_version[package][version.to_s]
        info = spec.info
        info = info.select { |p, i| @active_platforms.include?(p) }

        deps = {}
        info.flat_map { |_, i| i[:dependencies] }.each do |n, cs|
          deps[n] ||= []
          deps[n].concat cs
        end

        # FIXME: ruby_constraints ???

        deps
      end
    end

    def incompatibilities_for(package, version)
      deps = dependencies_for(package, version)

      # Versions sorted by value, not preference
      sorted_versions = versions_for(package)
      sorted_versions.sort!

      deps.map do |dep_name, constraints|
        # Build a range for all versions of this package with the same dependency
        low = high = sorted_versions.index(version)
        high += 1

        self_range = PubGrub::VersionRange.new(
          min: sorted_versions[low],
          max: sorted_versions[high],
          include_min: true,
          include_max: false
        )
        self_constraint = PubGrub::VersionConstraint.new(package, range: self_range)

        dep_package = @packages[dep_name]
        if !dep_package
          # TODO: PubGrub is able to handle this gracefully
          raise "Unknown package"
        end

        dep_constraint = PubGrub::VersionConstraint.new(dep_package, range: to_range(constraints))

        PubGrub::Incompatibility.new([
          PubGrub::Term.new(self_constraint, true),
          PubGrub::Term.new(dep_constraint, false)
        ], cause: :dependency)
      end
    end

    private

    def fetch_package_info(package)
      return if @specs_by_package_version.key?(package)

      specs = []
      @catalogs.each do |catalog|
        if info = catalog.gem_info(package.name)
          @cached_specs[catalog][package.name] ||=
            begin
              grouped_versions = info.to_a.map do |full_version, attributes|
                version, platform = full_version.split("-", 2)
                platform ||= "ruby"
                [version, platform, attributes]
              end.group_by(&:first)

              grouped_versions.map { |version, tuples| Spec.new(package.name, version, tuples.map { |_, p, a| [p, a] }) }
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

    def root_deps
      deps = {}

      full_requirements = @gemfile.gems.select do |_, _, options|
        !options[:path] && !options[:git]
      end.map do |name, constraints, _|
        deps[name] ||= []
        deps[name].concat constraints.flatten
      end

      platform_requirements = @gemfile.gems.select do |_, _, options|
        !options[:path] && !options[:git] && (!options[:platforms] || options[:platforms].include?(:mri))
      end.map do |name, constraints, _|
        deps[name] ||= []
        deps[name].concat constraints.flatten
      end

      deps.values.each(&:uniq!)

      deps
    end

    def to_range(constraints)
      Array(constraints).flatten.map do |constraint|
        op, ver = Paperback::Support::GemRequirement.parse(constraint)
        case op
        when "~>"
          # TODO: not sure this is correct for prereleases
          PubGrub::VersionRange.new(min: ver, max: ver.bump, include_min: true)
        when ">"
          PubGrub::VersionRange.new(min: ver)
        when ">="
          if ver == Gem::Version.new("0")
            PubGrub::VersionRange.any
          else
            PubGrub::VersionRange.new(min: ver, include_min: true)
          end
        when "<"
          PubGrub::VersionRange.new(max: ver)
        when "<="
          PubGrub::VersionRange.new(max: ver, include_max: true)
        when "="
          PubGrub::VersionRange.new(min: ver, max: ver, include_min: true, include_max: true)
        when "!="
          PubGrub::VersionRange.new(min: ver, max: ver, include_min: true, include_max: true).invert
        else
          raise "bad version specifier: #{op}"
        end
      end.inject(:intersect) || PubGrub::VersionRange.any
    end
  end
end
