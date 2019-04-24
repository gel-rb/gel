# frozen_string_literal: true

class Gel::StoreGem
  EXTENSION_SUBDIR_TOKEN = ".."

  attr_reader :root, :name, :version, :extensions, :info

  def initialize(root, name, version, extensions, info)
    @root = root
    @name = name
    @version = version
    @extensions = extensions unless extensions && extensions.empty?
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
    paths.concat Array(extensions) if extensions
    raise(paths.inspect) unless paths.all? { |path| path.is_a?(String) }
    paths
  end

  def bindir
    @info[:bindir] || "bin"
  end

  def dependencies
    @info[:dependencies]
  end

  def executables
    @info[:executables]
  end

  def path(file, subdir = nil)
    if subdir == EXTENSION_SUBDIR_TOKEN && extensions
      "#{extensions}/#{file}"
    else
      subdir ||= _default_require_path
      "#{root}/#{subdir}/#{file}"
    end
  end

  def libs
    _require_paths.each do |subdir|
      prefix = "#{root}/#{subdir}/"
      Dir["#{prefix}**/*.rb"].each do |path|
        next unless path.start_with?(prefix)
        file = path[prefix.size..-1].sub(/\.rb$/, "")
        yield file, subdir
      end
    end
  end

  private

  def gem_version
    @gem_version ||= Gel::Support::GemVersion.new(version)
  end

  def _require_paths
    @info[:require_paths]
  end

  def _default_require_path
    _require_paths.first
  end
end
