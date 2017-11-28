class Paperback::StoreGem
  attr_reader :root, :name, :version, :info

  def initialize(root, name, version, info)
    @root = root
    @name = name
    @version = version
    @info = info
  end

  def satisfies?(requirements)
    requirements.satisfied_by?(gem_version)
  end

  def require_paths
    _require_paths.map { |reqp| "#{root}/#{reqp}" }
  end

  def dependencies
    @info[:dependencies]
  end

  def path(file, subdir = nil)
    subdir ||= _default_require_path
    "#{root}/#{subdir}/#{file}"
  end

  private

  def gem_version
    @gem_version ||= Paperback::Support::GemVersion.new(version)
  end

  def _require_paths
    @info[:require_paths]
  end

  def _default_require_path
    _require_paths.first
  end
end
