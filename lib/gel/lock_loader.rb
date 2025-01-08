# frozen_string_literal: true

require_relative "resolved_gem_set"
require_relative "git_catalog"
require_relative "path_catalog"

require_relative "support/gem_platform"

class Gel::LockLoader
  attr_reader :gemfile

  def initialize(gem_set, gemfile = nil)
    @gem_set = gem_set
    @gemfile = gemfile
  end

  def gem_names
    @gem_set.gem_names
  end

  def activate(env, base_store, install: false, output: nil)
    locked_store = Gel::LockedStore.new(base_store)

    locks = {}

    if install
      require_relative "installer"
      installer = Gel::Installer.new(base_store)
    end

    gems_to_process = []
    if gemfile && env
      env.filtered_gems(gemfile.gems).each do |name, *|
        gems_to_process << name
      end
    elsif list = @gem_set.dependency_names
      gems_to_process = list
    end

    local_platform = Gel::Support::GemPlatform.local
    all_gems = @gem_set.gems

    deferred_direct_gem = lambda do |dir, name, version|
      -> { Gel::DirectGem.new(dir, name, version) }
    end

    processed_gems = {}
    while name = gems_to_process.shift
      next if processed_gems[name]
      processed_gems[name] = true

      next if Gel::Environment::IGNORE_LIST.include?(name)

      next unless all_versions = all_gems[name]

      resolved_gems = all_versions.select do |rg|
        local_platform =~ rg.platform || rg.platform.nil?
      end.sort_by { |rg| rg.platform&.size || 0 }.reverse

      next if resolved_gems.empty?

      resolved_gem = resolved_gems.first


      case resolved_gem.catalog
      when Gel::GitCatalog
        dir = resolved_gem.catalog.path

        installer.known_dependencies name => resolved_gem.deps.map(&:first) if installer
        installer&.load_git_gem(resolved_gem.catalog.remote, resolved_gem.catalog.revision, name)

        locks[name] = deferred_direct_gem.call(dir, name, resolved_gem.version)
      when Gel::PathCatalog
        path = resolved_gem.catalog.path

        dir = File.expand_path(path, File.dirname(@gem_set.filename))

        installer.known_dependencies name => resolved_gem.deps.map(&:first) if installer
        locks[name] = Gel::DirectGem.new(dir, name, resolved_gem.version)
      else
        unless resolved_gem = resolved_gems.find { |rg| base_store.gem?(name, rg.version, rg.platform) }
          if installer
            require_relative "catalog"

            catalogs = @gem_set.server_catalogs

            skipped_matches = []

            catalog_infos = catalogs.map { |c| c.gem_info(name) }
            resolved_gems.each do |rg|
              catalog_infos.each do |info|
                s = rg.platform ? "#{rg.version}-#{rg.platform}" : rg.version
                if i = info[s]
                  if i[:ruby] && !Gel::Support::GemRequirement.new(i[:ruby].split("&")).satisfied_by?(Gel::Support::GemVersion.new(RUBY_VERSION))
                    skipped_matches << s
                  else
                    resolved_gem = rg
                    break
                  end
                end
              end

              break if resolved_gem
            end

            if resolved_gem.nil?
              raise Gel::Error::UnsatisfiableRubyVersionError.new(name: name, running: RUBY_VERSION, attempted_platforms: skipped_matches)
            end

            installer.known_dependencies name => resolved_gem.deps.map(&:first)
            installer.install_gem(catalogs, name, resolved_gem.platform ? "#{resolved_gem.version}-#{resolved_gem.platform}" : resolved_gem.version)
          else
            raise Gel::Error::MissingGemError.new(name: name)
          end
        end

        locks[name] = resolved_gem.version.to_s
      end


      resolved_gem.deps.map(&:first).each do |dep_name|
        gems_to_process.unshift dep_name
      end
    end

    installer.wait(output) if installer

    locks.each do |name, locked|
      locks[name] = locked.call if locked.is_a?(Proc)
    end

    locked_store.lock(locks)

    locked_store
  end
end
