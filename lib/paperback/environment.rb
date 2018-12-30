# frozen_string_literal: true

require "rbconfig"

class Paperback::Environment
  IGNORE_LIST = %w(bundler)

  class << self
    attr_reader :store
    attr_accessor :gemfile
    attr_reader :architectures
  end
  self.gemfile = nil
  @active_lockfile = false
  @architectures = ["ruby"].freeze

  GEMFILE_PLATFORMS = begin
    v = RbConfig::CONFIG["ruby_version"].split(".")[0..1].inject(:+)
    ["ruby", "ruby_#{v}", "mri", "mri_#{v}"]
  end

  def self.platform?(platform)
    platform.nil? || architectures.include?(platform)
  end

  def self.store_set
    list = []
    architectures.each do |arch|
      list << Paperback::MultiStore.subkey(arch, true)
      list << Paperback::MultiStore.subkey(arch, false)
    end
    list
  end

  def self.activated_gems
    @activated ||= {}
  end

  def self.open(store)
    @store = store
  end

  def self.search_upwards(name, dir = Dir.pwd)
    until (file = File.join(dir, name)) && File.exist?(file)
      next_dir = File.dirname(dir)
      return nil if next_dir == dir
      dir = next_dir
    end
    file
  end

  def self.find_gemfile(path = nil)
    if path && @gemfile && @gemfile.filename != File.expand_path(path)
      raise "Cannot activate #{path.inspect}; already activated #{@gemfile.filename.inspect}"
    end
    return @gemfile.filename if @gemfile

    path ||= ENV["PAPERBACK_GEMFILE"]
    path ||= search_upwards("Gemfile")
    path ||= "Gemfile"

    raise "No Gemfile found in #{path.inspect}" unless File.exist?(path)

    path
  end

  def self.load_gemfile(path = nil)
    return if @gemfile

    path = find_gemfile(path)

    content = File.read(path)
    @gemfile = Paperback::GemfileParser.parse(content, path, 1)
  end

  def self.lockfile_name(gemfile = self.gemfile.filename)
    ENV["PAPERBACK_LOCKFILE"] ||
      (gemfile && File.exist?(gemfile + ".lock") && gemfile + ".lock") ||
      search_upwards("Gemfile.lock") ||
      "Gemfile.lock"
  end

  def self.lock(output: nil)
    Paperback::Environment.load_gemfile
    return if @active_lockfile

    lockfile = Paperback::Environment.lockfile_name
    if File.exist?(lockfile)
      loader = Paperback::LockLoader.new(lockfile, gemfile)
      # TODO
    end

    # HACK
    $: << File.expand_path("../../tmp/bootstrap/store/ruby/gems/molinillo-0.6.4/lib", __dir__)

    require_relative "catalog"
    all_sources = (@gemfile.sources | @gemfile.gems.flat_map { |_, _, o| o[:source] }).compact
    server_catalogs = all_sources.map { |s| Paperback::Catalog.new(s) }

    git_sources = @gemfile.gems.map { |_, _, o|
      if o[:git]
        [o[:git], o[:branch] || o[:ref]]
      end
    }.compact.uniq

    path_sources = @gemfile.gems.map { |_, _, o| o[:path] }.compact

    require_relative "git_depot"
    git_depot = Paperback::GitDepot.new(Paperback::Environment.store)

    require_relative "path_catalog"
    require_relative "git_catalog"

    catalogs =
      path_sources.map { |path| Paperback::PathCatalog.new(path) } +
      git_sources.map { |remote, ref| Paperback::GitCatalog.new(git_depot, remote, ref) } +
      [nil] +
      server_catalogs

    require_relative "specification_provider"
    provider = Paperback::SpecificationProvider.new(catalogs, ["ruby"])
    @gemfile.gems.select do |_, _, options|
      !options[:path] && !options[:git]
    end.each do |name, _, _|
      server_catalogs.each do |catalog|
        catalog.instance_variable_get(:@indexes).each do |index|
          catalog.send(index).instance_variable_get(:@pending_gems) << name
        end
      end
    end

    ui = Struct.new(:output) { include Molinillo::UI }.new(output || File.open(IO::NULL))

    resolver = Molinillo::Resolver.new(provider, ui)

    full_requirements = @gemfile.gems.map do |name, constraints, options|
      [Paperback::SpecificationProvider::Dep.new(name, constraints), options]
    end

    platform_requirements = @gemfile.gems.select do |_, _, options|
      next true unless platforms = options[:platforms]
      !([*platforms] & [:ruby, :mri]).empty?
    end.map do |name, constraints, _|
      Paperback::SpecificationProvider::Dep.new(name, constraints)
    end

    graph = resolver.resolve(platform_requirements)

    lock_content = []

    output_specs_for = lambda do |vertices|
      lock_content << "  specs:"
      vertices.each do |vertex|
        payload = vertex.payload
        next if payload.name == "bundler" || payload.name == "ruby"

        lock_content << "    #{payload.name} (#{payload.version})"
        payload.info.each do |(platform, attributes)|
          next unless platform == "ruby"

          deps = attributes[:dependencies]
          next unless deps && deps.first

          dep_lines = deps.map do |(dep_name, dep_requirements)|
            next dep_name if dep_requirements == [">= 0"] || dep_requirements == []

            req = Paperback::Support::GemRequirement.new(dep_requirements)
            req_strings = req.requirements.sort_by { |(_op, ver)| ver }.map { |(op, ver)| "#{op} #{ver}" }

            "#{dep_name} (#{req_strings.join(", ")})"
          end

          dep_lines.sort.each do |line|
            lock_content << "      #{line}"
          end
        end
      end
    end

    grouped_graph = graph.sort_by { |v| v.payload.name }.group_by { |v|
      v.payload.catalog.is_a?(Paperback::Catalog) ? nil : v.payload.catalog
    }
    server_gems = grouped_graph.delete(nil)

    grouped_graph.keys.sort_by do |catalog|
      case catalog
      when Paperback::GitCatalog
        [1, catalog.remote, catalog.revision]
      when Paperback::PathCatalog
        [2, catalog.path]
      end
    end.each do |catalog|
      case catalog
      when Paperback::GitCatalog
        lock_content << "GIT"
        lock_content << "  remote: #{catalog.remote}"
        lock_content << "  revision: #{catalog.revision}"
      when Paperback::PathCatalog
        lock_content << "PATH"
        lock_content << "  remote: #{catalog.path}"
      end

      output_specs_for.call(grouped_graph[catalog])
      lock_content << ""
    end

    lock_content << "GEM"
    server_catalogs.each do |catalog|
      lock_content << "  remote: #{catalog}"
    end
    output_specs_for.call(server_gems)

    lock_content << ""
    lock_content << "PLATFORMS"
    lock_content << "  ruby"
    lock_content << ""
    lock_content << "DEPENDENCIES"
    full_requirements.sort_by { |req, _| req.name }.each do |req, options|
      constraints = req.constraints.flatten
      bang = "!" if options[:path] || options[:git]
      if constraints == []
        lock_content << "  #{req.name}#{bang}"
      else
        r = Paperback::Support::GemRequirement.new(constraints)
        req_strings = r.requirements.sort_by { |(_op, ver)| ver }.map { |(op, ver)| "#{op} #{ver}" }

        lock_content << "  #{req.name} (#{req_strings.join(", ")})#{bang}"
      end
    end
    lock_content << ""
    lock_content << "RUBY VERSION"
    lock_content << "   #{RUBY_DESCRIPTION.split.first(2).join(" ")}"
    lock_content << ""
    lock_content << "BUNDLED WITH"
    lock_content << "   1.999"

    File.open(lockfile, "w") do |f|
      f.write(lock_content.join("\n") << "\n")
    end
  end

  def self.activate(install: false, output: nil)
    Paperback::Environment.load_gemfile
    return if @active_lockfile

    lockfile = Paperback::Environment.lockfile_name
    if File.exist?(lockfile)
      @active_lockfile = true
      loader = Paperback::LockLoader.new(lockfile, gemfile)

      loader.activate(Paperback::Environment, Paperback::Environment.store.inner, install: install, output: output)
    else
      raise "No lockfile found in #{lockfile.inspect}"
    end
  end

  def self.find_executable(exe, gem_name = nil, gem_version = nil)
    @store.each(gem_name) do |g|
      next if gem_version && g.version != gem_version
      return File.join(g.root, g.bindir, exe) if g.executables.include?(exe)
    end
    nil
  end

  def self.filtered_gems(gems = self.gemfile.gems)
    platforms = GEMFILE_PLATFORMS.map(&:to_s)
    gems = gems.reject { |g| g[2][:platforms] && (Array(g[2][:platforms]).map(&:to_s) & platforms).empty? }
    gems
  end

  def self.require_groups(*groups)
    gems = filtered_gems
    groups = [:default] if groups.empty?
    groups = groups.map(&:to_s)
    gems = gems.reject { |g| ((g[2][:groups] || [:default]).map(&:to_s) & groups).empty? }
    @gemfile.autorequire(self, gems)
  end

  def self.gem(name, *requirements, why: nil)
    return if IGNORE_LIST.include?(name)

    requirements = Paperback::Support::GemRequirement.new(requirements)

    if existing = activated_gems[name]
      if existing.satisfies?(requirements)
        return
      else
        why = " (#{why.join("; ")})" if why && why.first
        raise "already loaded gem #{name} #{existing.version}, which is incompatible with: #{requirements}#{why}"
      end
    end

    gem = @store.each(name).find do |g|
      g.satisfies?(requirements)
    end

    if gem
      activate_gem gem, why: why
    else
      why = " (#{why.join("; ")})" if why && why.first
      raise "unable to satisfy requirements for gem #{name}: #{requirements}#{why}"
    end
  end

  def self.gems_from_lock(name_version_pairs)
    gems = @store.gems(name_version_pairs)

    dirs = []
    gems.each do |name, g|
      dirs += g.require_paths
    end

    activated_gems.update gems
    $:.concat dirs
  end

  def self.activate_gem(gem, why: nil)
    return if activated_gems[gem.name] && activated_gems[gem.name].version == gem.version
    raise "already activated #{gem.name} #{activated_gems[gem.name].version}" if activated_gems[gem.name]

    gem.dependencies.each do |dep, reqs|
      self.gem(dep, *reqs.map { |(qual, ver)| "#{qual} #{ver}" }, why: ["required by #{gem.name} #{gem.version}", *why])
    end

    lib_dirs = gem.require_paths
    @store.prepare gem.name => gem.version

    activated_gems[gem.name] = gem
    $:.concat lib_dirs
  end

  def self.gem_has_file?(gem_name, path)
    @store.gems_for_lib(path) do |gem, subdir|
      if gem.name == gem_name && gem == activated_gems[gem_name]
        return gem.path(path, subdir)
      end
    end

    false
  end

  def self.scoped_require(gem_name, path)
    if full_path = gem_has_file?(gem_name, path)
      require full_path
    else
      raise LoadError, "No file #{path.inspect} found in gem #{gem_name.inspect}"
    end
  end

  def self.resolve_gem_path(path)
    if @store && !path.start_with?("/")
      results = []
      @store.gems_for_lib(path) do |gem, subdir|
        results << [gem, subdir]
        break if activated_gems[gem.name] == gem
      end
      result = results.find { |g, _| activated_gems[g.name] == g } || results.first

      if result
        activate_gem result[0], why: ["provides #{path.inspect}"]
        return result[0].path(path, result[1])
      end
    end

    path
  end
end
