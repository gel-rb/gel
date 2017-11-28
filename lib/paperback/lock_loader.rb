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
