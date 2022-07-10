# frozen_string_literal: true

require_relative "platform"

class Gel::CatalogSet
  CatalogEntry = Struct.new(:catalog, :name, :version, :info) do
    def gem_version
      @gem_version ||= Gel::Support::GemVersion.new(version)
    end
  end

  def initialize(catalogs, gemfile)
    @catalogs = catalogs
    @gemfile = gemfile

    @cached_specs = Hash.new { |h, k| h[k] = {} }
    @specs_by_package_version = {}
  end

  def catalog_for_version(package, version)
    @specs_by_package_version[package.name][version.to_s]&.catalog
  end

  def entries_for(package)
    fetch_package_info(package)

    @specs_by_package_version[package.name].values.select do |spec|
      available_platforms = spec.info.map(&:first)
      Gel::Platform.match(package.platform, available_platforms)
    end
  end

  # Returns a list of [name, version_contraint] pairs representing the
  # specified package's dependencies. Note that a given +name+ may
  # appear multiple times, and the resulting dependency is the
  # intersection of all constraints.
  def dependencies_for(package, version)
    fetch_package_info(package) # probably already done, can't hurt

    spec = @specs_by_package_version[package.name][version.to_s]

    raise "missing spec #{package.inspect} / #{version.inspect}" if spec.nil?

    info = spec.info

    available_platforms = info.map(&:first)
    matching_platform = Gel::Platform.match(package.platform, available_platforms)

    info = info.select { |p, i| p == matching_platform }

    # FIXME: ruby_constraints ???

    info.flat_map { |_, i| i[:dependencies] }
  end

  def platform_for(package, version)
    fetch_package_info(package) # probably already done, can't hurt

    spec = @specs_by_package_version[package.name][version.to_s]

    info = spec.info

    available_platforms = info.map(&:first)
    Gel::Platform.match(package.platform, available_platforms)
  end

  private

  def fetch_package_info(package)
    return if @specs_by_package_version.key?(package.name)

    catalogs = @catalogs

    if gem_entry = @gemfile.gems.assoc(package.name)
      if specified_sources = gem_entry[2][:source]
        catalogs = catalogs.select do |catalog|
          catalog.is_a?(Gel::Catalog) &&
            Array(specified_sources).any? { |s| catalog.match?(s) }
        end
      end
    end

    specs = []
    catalogs.each do |catalog|
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

            grouped_versions.map { |version, tuples| CatalogEntry.new(catalog, package.name, version, tuples.map { |_, p, a| [p, a] }) }
          end

        specs.concat @cached_specs[catalog][package.name]
      end
    end

    @specs_by_package_version[package.name] = {}
    specs.each do |spec|
      # TODO: are we going to find specs in multiple catalogs this way?
      @specs_by_package_version[package.name][spec.version] = spec
    end
  end
end
