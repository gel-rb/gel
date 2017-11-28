class Paperback::LockLoader
  attr_reader :filename

  def initialize(filename)
    @filename = filename
  end

  def activate(env, base_store)
    locked_store = Paperback::LockedStore.new(base_store)

    lock_content = Paperback::LockParser.new.parse(File.read(filename))
    locks = {}

    lock_content.each do |(section, body)|
      case section
      when "GEM"
        specs = body["specs"]
        specs.each do |gem_spec, dep_specs|
          gem_spec =~ /\A(.+) \(([^-]+)(?:-(.+))?\)\z/
          name, version, _platform = $1, $2, $3
          locks[name] = version
        end
      when "PATH", "GIT"
        specs = body["specs"]
        specs.each do |gem_spec, dep_specs|
          gem_spec =~ /\A(.+) \(([^-]+)(?:-(.+))?\)\z/
          name, version, _platform = $1, $2, $3
          if section == "GIT"
            # Massively cheating for now
            dir = "~/.rbenv/gems/2.4.0/bundler/gems/#{name}-#{body["revision"].first[0, 12]}"
          else
            dir = File.expand_path(body["remote"].first, File.dirname(filename))
            if Dir.exist?("#{dir}/#{name}")
              dir = "#{dir}/#{name}"
            end
          end
          if dep_specs
            deps = dep_specs.map do |spec|
              spec =~ /\A(.+) \((.+)\)\z/
              [$1, $2.split(", ").map { |req| Paperback::Support::GemRequirement.parse(req) }]
            end
          else
            deps = []
          end
          locks[name] = Paperback::StoreGem.new(dir, name, version, require_paths: ["lib"], dependencies: deps)
        end
      when "PLATFORMS", "DEPENDENCIES"
      when "BUNDLED WITH"
      else
        warn "Unknown lockfile section #{section.inspect}"
      end
    end

    locked_store.lock(locks)
    env.activate(locked_store)

    locks.keys.each do |gem_name|
      env.gem(gem_name)
    end
  end
end
