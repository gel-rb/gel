class Paperback::Environment
  def self.activate(store)
    @store = store
  end

  def self.gem(name, *requirements)
    activate_gem name, requirements.first
  end

  def self.activate_gem(name, version)
    info = @store.gem_info(name, version)
    lib_dirs = info[:require_paths].map { |s| File.expand_path(s, "#{@store.root}/gems/#{name}-#{version}/") }
    $:.concat lib_dirs
  end

  def self.require(path)
    options = @store.gems_for_lib(path)
    super if options.empty?
    activate_gem(*options.first)
    super
  end
end
