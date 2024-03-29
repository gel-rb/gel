require_relative '../pub_grub/package'
require_relative '../pub_grub/version_constraint'
require_relative '../pub_grub/incompatibility'
require_relative '../pub_grub/basic_package_source'

module Gel::Vendor::PubGrub
  class StaticPackageSource < BasicPackageSource
    class DSL
      def initialize(packages, root_deps)
        @packages = packages
        @root_deps = root_deps
      end

      def root(deps:)
        @root_deps.update(deps)
      end

      def add(name, version, deps: {})
        version = Gem::Version.new(version)
        @packages[name] ||= {}
        raise ArgumentError, "#{name} #{version} declared twice" if @packages[name].key?(version)
        @packages[name][version] = deps
      end
    end

    def initialize
      @root_deps = {}
      @packages = {}

      yield DSL.new(@packages, @root_deps)

      super()
    end

    def all_versions_for(package)
      @packages[package].keys
    end

    def root_dependencies
      @root_deps
    end

    def dependencies_for(package, version)
      @packages[package][version]
    end

    def parse_dependency(package, dependency)
      return false unless @packages.key?(package)

      Gel::Vendor::PubGrub::RubyGems.parse_constraint(package, dependency)
    end
  end
end
