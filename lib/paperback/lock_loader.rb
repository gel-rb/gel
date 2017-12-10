require "uri"

class Paperback::LockLoader
  attr_reader :filename

  def initialize(filename)
    @filename = filename
  end

  def activate(env, base_store, install: false, output: nil)
    locked_store = Paperback::LockedStore.new(base_store)

    lock_content = Paperback::LockParser.new.parse(File.read(filename))
    locks = {}

    if install
      installer = Paperback::Installer.new(base_store)
    end

    lock_content.each do |(section, body)|
      case section
      when "GEM"
        specs = body["specs"]
        catalogs = body["remote"].map { |r| Paperback::Catalog.new(URI(r)) }
        specs.each do |gem_spec, dep_specs|
          gem_spec =~ /\A(.+) \(([^-]+)(?:-(.+))?\)\z/
          name, version, _platform = $1, $2, $3

          if installer
            if dep_specs
              dep_names = dep_specs.map { |spec|
                spec =~ /\A(.+?)(?: \((.+)\))?\z/
                $1
              }
              installer.known_dependencies name => dep_names
            end

            if !base_store.gem?(name, version)
              installer.install_gem(catalogs, name, version)
            end
          end

          locks[name] = version
        end
      when "PATH", "GIT"
        specs = body["specs"]
        specs.each do |gem_spec, dep_specs|
          gem_spec =~ /\A(.+) \(([^-]+)(?:-(.+))?\)\z/
          name, version, _platform = $1, $2, $3
          if section == "GIT"
            dir_name = File.basename(body["remote"].first, ".git")
            # Massively cheating for now
            dir = "~/.rbenv/gems/2.4.0/bundler/gems/#{dir_name}-#{body["revision"].first[0, 12]}"
          else
            dir = File.expand_path(body["remote"].first, File.dirname(filename))
          end
          if dep_specs
            dep_names = dep_specs.map { |spec|
              spec =~ /\A(.+?)(?: \((.+)\))?\z/
              $1
            }
            installer.known_dependencies name => dep_names if installer

            deps = dep_specs.map do |spec|
              spec =~ /\A(.+?)(?: \((.+)\))?\z/
              [$1, ($2 ? $2.split(", ") : []).map { |req| Paperback::Support::GemRequirement.parse(req) }]
            end
          else
            deps = []
          end
          locks[name] = Paperback::DirectGem.new(dir, name, version)
        end
      when "PLATFORMS", "DEPENDENCIES"
      when "BUNDLED WITH"
      else
        warn "Unknown lockfile section #{section.inspect}"
      end
    end

    installer.wait(output) if installer

    locked_store.lock(locks)

    if env
      env.activate(locked_store)

      locks.keys.each do |gem_name|
        env.gem(gem_name) rescue nil
      end
    end
  end
end
