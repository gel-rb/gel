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

    filtered_gems = Hash.new(nil)
    top_gems = []
    if gemfile && env
      gemfile.gems.each do |name, *|
        filtered_gems[name] = false
      end
      env.filtered_gems(gemfile.gems).each do |name, *|
        top_gems << name
        filtered_gems[name] = true
      end
    elsif list = @gem_set.dependency_names
      top_gems = list
      top_gems.each do |name|
        filtered_gems[name] = true
      end
    end

    # For each gem name, we now decide which of the known variants we
    # will attempt to use *if* we end up trying to load this gem. This
    # *will* encounter gems that have no supported variant, but we
    # assume those will never be requested.
    platform_gems = {}
    local_platform = Gel::Support::GemPlatform.local
    @gem_set.gems.each do |name, resolved_gems|
      next if Gel::Environment::IGNORE_LIST.include?(name)

      fallback = resolved_gems.find { |rg| rg.platform.nil? }
      best_choice = resolved_gems.find { |rg| local_platform =~ rg.platform } || fallback

      if best_choice
        platform_gems[name] = best_choice
        installer.known_dependencies name => best_choice.deps.map(&:first) if installer
      end
    end

    walk = lambda do |name|
      if resolved_gem = platform_gems[name]
        next if env && !env.platform?(resolved_gem.platform)

        filtered_gems[name] = true

        resolved_gem.deps.map(&:first).each do |dep_name|
          walk[dep_name] unless filtered_gems[dep_name]
        end
      end
    end

    top_gems.each(&walk)

    platform_gems.each do |name, resolved_gem|
      next unless filtered_gems[name]

      case resolved_gem.catalog
      when Gel::GitCatalog
        dir = resolved_gem.catalog.path

        installer&.load_git_gem(resolved_gem.catalog.remote, resolved_gem.catalog.revision, name)

        locks[name] = -> { Gel::DirectGem.new(dir, name, resolved_gem.version) }
      when Gel::PathCatalog
        path = resolved_gem.catalog.path

        dir = File.expand_path(path, File.dirname(@gem_set.filename))

        locks[name] = Gel::DirectGem.new(dir, name, resolved_gem.version)
      else
        if installer && !base_store.gem?(name, resolved_gem.version, resolved_gem.platform)
          require_relative "catalog"
          catalogs = @gem_set.server_catalogs
          installer.install_gem(catalogs, name, resolved_gem.platform ? "#{resolved_gem.version}-#{resolved_gem.platform}" : resolved_gem.version)
        end

        locks[name] = resolved_gem.version.to_s
      end
    end

    installer.wait(output) if installer

    locks.each do |name, locked|
      locks[name] = locked.call if locked.is_a?(Proc)
    end

    locked_store.lock(locks)

    if env
      env.open(locked_store)

      env.gems_from_lock(locks)
    end

    locked_store
  end
end
