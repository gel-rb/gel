# frozen_string_literal: true

require_relative "git_depot"

class Paperback::LockLoader
  attr_reader :filename
  attr_reader :gemfile

  def initialize(filename, gemfile = nil)
    @filename = filename
    @gemfile = gemfile
  end

  def lock_content
    @lock_content ||= Paperback::LockParser.new.parse(File.read(filename))
  end

  def each_gem
    lock_content.each do |(section, body)|
      case section
      when "GEM", "PATH", "GIT"
        specs = body["specs"]
        specs.each do |gem_spec, dep_specs|
          gem_spec =~ /\A(.+) \(([^-]+)(?:-(.+))?\)\z/
          name, version, platform = $1, $2, $3

          if dep_specs
            deps = dep_specs.map do |spec|
              spec =~ /\A(.+?)(?: \((.+)\))?\z/
              [$1, $2 ? $2.split(", ") : []]
            end
          else
            deps = []
          end

          sym =
            case section
            when "GEM"; :gem
            when "PATH"; :path
            when "GIT"; :git
            end
          yield sym, body, name, version, platform, deps
        end
      when "PLATFORMS", "DEPENDENCIES"
      when "BUNDLED WITH"
      else
        warn "Unknown lockfile section #{section.inspect}"
      end
    end
  end

  def activate(env, base_store, install: false, output: nil)
    locked_store = Paperback::LockedStore.new(base_store)

    locks = {}

    if install
      require_relative "installer"
      installer = Paperback::Installer.new(base_store)
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
    elsif pair = lock_content.assoc("DEPENDENCIES")
      _, list = pair
      top_gems = list.map { |name| name.split(" ", 2)[0].chomp("!") }
      top_gems.each do |name|
        filtered_gems[name] = true
      end
    end

    gems = {}
    each_gem do |section, body, name, version, platform, deps|
      next if env && !env.platform?(platform)

      gems[name] = [section, body, version, platform, deps]

      installer.known_dependencies name => deps.map(&:first) if installer
    end

    walk = lambda do |name|
      filtered_gems[name] = true
      next unless gems[name]
      gems[name].last.map(&:first).each do |dep_name|
        walk[dep_name] unless filtered_gems[dep_name]
      end
    end

    top_gems.each(&walk)

    git_depot = Paperback::GitDepot.new(base_store)

    gems.each do |name, (section, body, version, platform, _deps)|
      next unless filtered_gems[name]

      if section == :gem
        if installer && !base_store.gem?(name, version, platform)
          require_relative "catalog"
          catalogs = body["remote"].map { |r| Paperback::Catalog.new(r) }
          installer.install_gem(catalogs, name, platform ? "#{version}-#{platform}" : version)
        end

        locks[name] = version
      else
        if section == :git
          remote = body["remote"].first
          revision = body["revision"].first

          dir = git_depot.git_path(remote, revision)
          if installer && !Dir.exist?(dir)
            installer.load_git_gem(remote, revision, name)

            locks[name] = -> { Paperback::DirectGem.new(dir, name, version) }
            next
          end
        else
          dir = File.expand_path(body["remote"].first, File.dirname(filename))
        end

        locks[name] = Paperback::DirectGem.new(dir, name, version)
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
  end
end
