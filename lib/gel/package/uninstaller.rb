# frozen_string_literal: true

require_relative "../package"
require_relative "../util"

class Gel::Package::Uninstaller
  def initialize(store)
    @store = store
  end

  def uninstall(name, version, output: $stderr)
    paths_to_remove = []

    output.puts "Removing #{name} #{version}..."

    @store.remove_gem(name, version) do |gem_root, ext_root|
      paths_to_remove << gem_root
      paths_to_remove << ext_root if ext_root
    end

    paths_to_remove.each do |path|
      output.puts "  #{path}"
      Gel::Util.rm_rf(path)
    end
  end
end
