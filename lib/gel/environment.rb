# frozen_string_literal: true

require "rbconfig"

class Gel::Environment
  IGNORE_LIST = %w(bundler gel rubygems-update)

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

  def self.config
    @config ||= Gel::Config.new
  end

  def self.store_set
    list = []
    architectures.each do |arch|
      list << Gel::MultiStore.subkey(arch, true)
      list << Gel::MultiStore.subkey(arch, false)
    end
    list
  end

  def self.activated_gems
    @activated ||= {}
  end

  def self.open(store)
    @store = store
  end

  def self.original_rubylib
    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    lib.delete File.expand_path("compatibility", __dir__)
    #lib.delete File.expand_path("..", __dir__)
    return nil if lib.empty?
    lib.join(File::PATH_SEPARATOR)
  end

  def self.modified_rubylib
    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    dir = File.expand_path("compatibility", __dir__)
    lib.unshift dir unless lib.include?(dir)
    #dir = File.expand_path("..", __dir__)
    #lib.unshift dir unless lib.include?(dir)
    lib.join(File::PATH_SEPARATOR)
  end

  def self.search_upwards(name, dir = Dir.pwd)
    until (file = File.join(dir, name)) && File.exist?(file)
      next_dir = File.dirname(dir)
      return nil if next_dir == dir
      dir = next_dir
    end
    file
  end

  def self.find_gemfile(path = nil, error: true)
    if path && @gemfile && @gemfile.filename != File.expand_path(path)
      raise "Cannot activate #{path.inspect}; already activated #{@gemfile.filename.inspect}"
    end
    return @gemfile.filename if @gemfile

    path ||= ENV["GEL_GEMFILE"]
    path ||= search_upwards("Gemfile")
    path ||= "Gemfile"

    if File.exist?(path)
      path
    elsif error
      raise "No Gemfile found in #{path.inspect}"
    end
  end

  def self.load_gemfile(path = nil, error: true)
    return @gemfile if @gemfile

    path = find_gemfile(path, error: error)
    return if path.nil?

    content = File.read(path)
    @gemfile = Gel::GemfileParser.parse(content, path, 1)
  end

  def self.lockfile_name(gemfile = self.gemfile&.filename)
    ENV["GEL_LOCKFILE"] ||
      (gemfile && File.exist?(gemfile + ".lock") && gemfile + ".lock") ||
      search_upwards("Gemfile.lock") ||
      "Gemfile.lock"
  end

  def self.lock(store: store(), output: nil, gemfile: Gel::Environment.load_gemfile, lockfile: Gel::Environment.lockfile_name, catalog_options: {}, preference_strategy: nil)
    output = nil if $DEBUG

    if lockfile && File.exist?(lockfile)
      loader = Gel::LockLoader.new(lockfile, gemfile)
    end

    require_relative "catalog"
    all_sources = (gemfile.sources | gemfile.gems.flat_map { |_, _, o| o[:source] }).compact
    local_source = all_sources.delete(:local)
    server_gems = gemfile.gems.select { |_, _, o| !o[:path] && !o[:git] }.map(&:first)
    catalog_pool = Gel::WorkPool.new(8, name: "gel-catalog")
    server_catalogs = all_sources.map { |s| Gel::Catalog.new(s, initial_gems: server_gems, work_pool: catalog_pool, **catalog_options) }

    require_relative "store_catalog"
    local_catalogs = local_source ? [Gel::StoreCatalog.new(store)] : []

    git_sources = gemfile.gems.map { |_, _, o|
      if o[:git]
        if o[:branch]
          [o[:git], :branch, o[:branch]]
        elsif o[:tag]
          [o[:git], :tag, o[:tag]]
        else
          [o[:git], :ref, o[:ref]]
        end
      end
    }.compact.uniq

    path_sources = gemfile.gems.map { |_, _, o| o[:path] }.compact

    require_relative "git_depot"
    git_depot = Gel::GitDepot.new(store)

    require_relative "path_catalog"
    require_relative "git_catalog"

    catalogs =
      path_sources.map { |path| Gel::PathCatalog.new(path) } +
      git_sources.map { |remote, ref_type, ref| Gel::GitCatalog.new(git_depot, remote, ref_type, ref) } +
      [nil] +
      local_catalogs +
      server_catalogs

    Gel::WorkPool.new(8, name: "gel-catalog-prep") do |pool|
      if output
        output.print "Fetching sources..."
      else
        Gel::Httpool::Logger.info "Fetching sources..."
      end

      catalogs.each do |catalog|
        next if catalog.nil?

        pool.queue("catalog") do
          catalog.prepare
          output.print "." if output
        end
      end
    end

    begin
      app_store = Gel::Environment.store

      base_store = app_store
      base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

      # Work around the fact Gel::Environment is a singleton: we really
      # want to treat the environment we're running in separately from
      # the application's environment we're working on. But for now, we
      # can just cheat and swap them.
      @store = base_store

      if base_store.each("pub_grub").none?
        require_relative "work_pool"

        Gel::WorkPool.new(2) do |work_pool|
          catalog = Gel::Catalog.new("https://rubygems.org", work_pool: work_pool)

          install_gem([catalog], "pub_grub", [">= 0.5.0"])
        end
      end

      gem "pub_grub"
    ensure
      @store = app_store
    end
    require_relative "pub_grub/source"

    strategy = loader && preference_strategy && preference_strategy.call(loader)
    source = Gel::PubGrub::Source.new(gemfile, catalogs, ["ruby"], strategy)
    solver = PubGrub::VersionSolver.new(source: source)
    solver.define_singleton_method(:next_package_to_try) do
      self.solution.unsatisfied.min_by do |term|
        package = term.package
        versions = self.source.versions_for(package, term.constraint.range)

        if strategy
          strategy.package_priority(package, versions) + @package_depth[package]
        else
          @package_depth[package]
        end * 1000 + versions.count
      end.package
    end

    if output
      output.print "\nResolving dependencies..."
      t = Time.now
      until solver.solved?
        solver.work
        if Time.now > t + 0.1
          output.print "."
          t = Time.now
        end
      end
      output.puts
    else
      PubGrub.logger.info "Resolving dependencies..."
      solver.work until solver.solved?
    end

    solution = solver.result
    solution.delete(source.root)

    catalog_pool.stop

    lock_content = []

    output_specs_for = lambda do |results|
      lock_content << "  specs:"
      results.each do |(package, version)|
        next if package.name == "bundler" || package.name == "ruby" || package.name =~ /^~/

        lock_content << "    #{package} (#{version})"

        deps = source.dependencies_for(package, version)
        next unless deps && deps.first

        dep_lines = deps.map do |(dep_name, dep_requirements)|
          next dep_name if dep_requirements == [">= 0"] || dep_requirements == []

          req = Gel::Support::GemRequirement.new(dep_requirements)
          req_strings = req.requirements.sort_by { |(_op, ver)| ver }.map { |(op, ver)| "#{op} #{ver}" }

          "#{dep_name} (#{req_strings.join(", ")})"
        end

        dep_lines.sort.each do |line|
          lock_content << "      #{line}"
        end
      end
    end

    grouped_graph = solution.sort_by { |package,_| package.name }.group_by { |(package, version)|
      spec = source.spec_for_version(package, version)
      catalog = spec.catalog
      catalog.is_a?(Gel::Catalog) || catalog.is_a?(Gel::StoreCatalog) ? nil : catalog
    }
    server_gems = grouped_graph.delete(nil)

    grouped_graph.keys.sort_by do |catalog|
      case catalog
      when Gel::GitCatalog
        [1, catalog.remote, catalog.revision]
      when Gel::PathCatalog
        [2, catalog.path]
      end
    end.each do |catalog|
      case catalog
      when Gel::GitCatalog
        lock_content << "GIT"
        lock_content << "  remote: #{catalog.remote}"
        lock_content << "  revision: #{catalog.revision}"
        lock_content << "  #{catalog.ref_type}: #{catalog.ref}" if catalog.ref
      when Gel::PathCatalog
        lock_content << "PATH"
        lock_content << "  remote: #{catalog.path}"
      end

      output_specs_for.call(grouped_graph[catalog])
      lock_content << ""
    end

    if server_gems
      lock_content << "GEM"
      server_catalogs.each do |catalog|
        lock_content << "  remote: #{catalog}"
      end
      output_specs_for.call(server_gems)
      lock_content << ""
    end

    lock_content << "PLATFORMS"
    lock_content << "  ruby"
    lock_content << ""

    lock_content << "DEPENDENCIES"

    bang_deps = gemfile.gems.select { |_, _, options|
      options[:path] || options[:git] || options[:source]
    }.map { |name, _, _| name }

    root_deps = source.root_dependencies
    root_deps.sort_by { |name,_| name }.each do |name, constraints|
      next if name =~ /^~/

      bang = "!" if bang_deps.include?(name)
      if constraints == []
        lock_content << "  #{name}#{bang}"
      else
        r = Gel::Support::GemRequirement.new(constraints)
        req_strings = r.requirements.sort_by { |(_op, ver)| ver }.map { |(op, ver)| "#{op} #{ver}" }

        lock_content << "  #{name} (#{req_strings.join(", ")})#{bang}"
      end
    end
    lock_content << ""

    unless gemfile.ruby.empty?
      lock_content << "RUBY VERSION"
      lock_content << "   #{RUBY_DESCRIPTION.split.first(2).join(" ")}"
      lock_content << ""
    end

    if loader&.bundler_version
      lock_content << "BUNDLED WITH"
      lock_content << "   #{loader.bundler_version}"
      lock_content << ""
    end

    lock_body = lock_content.join("\n")

    if lockfile
      output.puts "Writing lockfile to #{File.expand_path(lockfile)}" if output
      File.write(lockfile, lock_body)
    end
    lock_body
  end

  def self.install_gem(catalogs, gem_name, requirements = nil, output: nil)
    base_store = Gel::Environment.store
    base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

    req = Gel::Support::GemRequirement.new(requirements)
    #base_store.each(gem_name) do |g|
    #  return false if g.satisfies?(req)
    #end

    require_relative "installer"
    installer = Gel::Installer.new(base_store)

    found_any = false
    catalogs.each do |catalog|
      # TODO: Hand this over to resolution so we pick up dependencies
      # too

      info = catalog.gem_info(gem_name)
      next if info.nil?

      found_any = true
      version = info.keys.
        map { |v| Gel::Support::GemVersion.new(v.split("-", 2).first) }.
        sort_by { |v| [v.prerelease? ? 0 : 1, v] }.
        reverse.find { |v| req.satisfied_by?(v) }
      next if version.nil?

      return false if base_store.gem?(gem_name, version.to_s)

      installer.install_gem([catalog], gem_name, version.to_s)

      installer.wait(output)

      return true
    end

    if found_any
      raise "no version of gem #{gem_name.inspect} satifies #{requirements.inspect}"
    else
      raise "unknown gem #{gem_name.inspect}"
    end
  end

  def self.activate(install: false, output: nil, error: true)
    loaded = Gel::Environment.load_gemfile
    return if loaded.nil?
    return if @active_lockfile

    lockfile = Gel::Environment.lockfile_name
    unless File.exist?(lockfile)
      lock(output: $stderr, lockfile: lockfile)
    end

    @active_lockfile = true
    loader = Gel::LockLoader.new(lockfile, gemfile)

    base_store = Gel::Environment.store
    base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

    loader.activate(Gel::Environment, base_store, install: install, output: output)
  end

  def self.activate_for_executable(exes, install: false, output: nil)
    loader = nil
    if Gel::Environment.load_gemfile(error: false)
      lockfile = Gel::Environment.lockfile_name
      unless File.exist?(lockfile)
        lock(output: $stderr, lockfile: lockfile)
      end

      loader = Gel::LockLoader.new(lockfile, gemfile)

      base_store = Gel::Environment.store
      base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

      locked_store = loader.activate(nil, base_store, install: install, output: output)

      exes.each do |exe|
        if locked_store.each.any? { |g| g.executables.include?(exe) }
          activate(install: install, output: output)
          return :lock
        end
      end
    end

    locked_gems = loader ? loader.gem_names : []

    @gemfile = nil
    exes.each do |exe|
      candidates = @store.each.select do |g|
        !locked_gems.include?(g.name) && g.executables.include?(exe)
      end.group_by(&:name)

      case candidates.size
      when 0
        nil
      when 1
        gem(candidates.keys.first)
        return :gem
      else
        # Multiple gems can supply this executable; do we have any
        # useful way of deciding which one should win? One obvious
        # tie-breaker: if a gem's name matches the executable, it wins.

        if candidates.keys.include?(exe)
          gem(exe)
        else
          gem(candidates.keys.first)
        end

        return :gem
      end
    end

    nil
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
    gems = gems.reject { |g| ((g[2][:group] || [:default]).map(&:to_s) & groups).empty? }
    @gemfile.autorequire(self, gems)
  end

  def self.find_gem(name, *requirements, &condition)
    requirements = Gel::Support::GemRequirement.new(requirements)

    @store.each(name).find do |g|
      g.satisfies?(requirements) && (!condition || condition.call(g))
    end
  end

  def self.gem(name, *requirements, why: nil)
    return if IGNORE_LIST.include?(name)

    requirements = Gel::Support::GemRequirement.new(requirements)

    if existing = activated_gems[name]
      if existing.satisfies?(requirements)
        return
      else
        why = " (#{why.join("; ")})" if why && why.first
        raise LoadError, "already loaded gem #{name} #{existing.version}, which is incompatible with: #{requirements}#{why}"
      end
    end

    gem = @store.each(name).find do |g|
      g.satisfies?(requirements)
    end

    if gem
      activate_gem gem, why: why
    else
      why = " (#{why.join("; ")})" if why && why.first
      raise LoadError, "unable to satisfy requirements for gem #{name}: #{requirements}#{why}"
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
    raise LoadError, "already activated #{gem.name} #{activated_gems[gem.name].version}" if activated_gems[gem.name]

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
