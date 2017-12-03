class Paperback::StoreGem
  EXTENSION_SUBDIR_TOKEN = "..".freeze

  attr_reader :root, :name, :version, :extensions, :info

  def initialize(root, name, version, extensions, info)
    @root = root
    @name = name
    @version = version
    @extensions = extensions
    @info = info
  end

  def ==(other)
    other.class == self.class && @name == other.name && @version == other.version
  end

  def hash
    @name.hash ^ @version.hash
  end

  def satisfies?(requirements)
    requirements.satisfied_by?(gem_version)
  end

  def require_paths
    paths = _require_paths.map { |reqp| "#{root}/#{reqp}" }
    paths << extensions if extensions
    paths
  end

  def dependencies
    @info[:dependencies]
  end

  def path(file, subdir = nil)
    if subdir == EXTENSION_SUBDIR_TOKEN && extensions
      "#{extensions}/#{file}"
    else
      subdir ||= _default_require_path
      "#{root}/#{subdir}/#{file}"
    end
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
