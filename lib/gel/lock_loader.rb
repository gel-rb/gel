# frozen_string_literal: true

require_relative "resolved_gem_set"

class Gel::LockLoader
  attr_reader :gemfile

  def initialize(filename, gemfile = nil)
    @gem_set = Gel::ResolvedGemSet.load(filename)
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
    elsif list = @gem_set.dependencies
      top_gems = list
      top_gems.each do |name|
        filtered_gems[name] = true
      end
    end

    @gem_set.gems.each do |name, resolved_gems|
      resolved_gems.each do |resolved_gem|
        next if env && !env.platform?(resolved_gem.platform)

        installer.known_dependencies name => resolved_gem.deps.map(&:first) if installer
      end
    end

    walk = lambda do |name|
      filtered_gems[name] = true

      @gem_set.gems[name]&.each do |resolved_gem|
        next if env && !env.platform?(resolved_gem.platform)
        resolved_gem.deps.map(&:first).each do |dep_name|
          walk[dep_name] unless filtered_gems[dep_name]
        end
      end
    end

    top_gems.each(&walk)

    require_relative "git_depot"
    require_relative "work_pool"

    Gel::WorkPool.new(8) do |work_pool|
      git_depot = Gel::GitDepot.new(base_store)

      @gem_set.gems.each do |name, resolved_gems|
        next unless filtered_gems[name]

        resolved_gems.each do |resolved_gem|
          next if env && !env.platform?(resolved_gem.platform)

          if resolved_gem.type == :gem
            if installer && !base_store.gem?(name, resolved_gem.version, resolved_gem.platform)
              require_relative "catalog"
              catalogs = resolved_gem.body["remote"].map { |r| Gel::Catalog.new(r, work_pool: work_pool) }
              installer.install_gem(catalogs, name, resolved_gem.platform ? "#{resolved_gem.version}-#{resolved_gem.platform}" : resolved_gem.version)
            end

            locks[name] = resolved_gem.version
          else
            if resolved_gem.type == :git
              remote = resolved_gem.body["remote"].first
              revision = resolved_gem.body["revision"].first

              dir = git_depot.git_path(remote, revision)
              if installer && !Dir.exist?(dir)
                installer.load_git_gem(remote, revision, name)

                locks[name] = -> { Gel::DirectGem.new(dir, name, resolved_gem.version) }
                next
              end
            else
              dir = File.expand_path(resolved_gem.body["remote"].first, File.dirname(@gem_set.filename))
            end

            locks[name] = Gel::DirectGem.new(dir, name, resolved_gem.version)
          end
        end
      end

      installer.wait(output) if installer

      locks.each do |name, locked|
        locks[name] = locked.call if locked.is_a?(Proc)
      end
    end

    locked_store.lock(locks)

    if env
      env.open(locked_store)

      env.gems_from_lock(locks)
    end

    locked_store
  end
end
