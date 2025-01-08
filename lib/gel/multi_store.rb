# frozen_string_literal: true

require "rbconfig"
require_relative "stub_set"

class Gel::MultiStore
  VERSION = "#{RbConfig::CONFIG["ruby_version"]}"

  attr_reader :root
  attr_reader :monitor

  def initialize(root, stores)
    @root = root && File.realpath(File.expand_path(root))
    @stores = stores

    @monitor = Monitor.new
  end

  def marshal_dump
    [@root, @stores]
  end

  def marshal_load(v)
    @root, @stores = v
    @monitor = Monitor.new
  end

  def stub_set
    @stub_set ||= Gel::StubSet.new(@root)
  end

  def paths
    @stores.values.flat_map(&:paths).uniq
  end

  def [](architecture, version = false)
    @stores[self.class.subkey(architecture, version)]
  end

  def self.subkey(architecture, version)
    architecture ||= "ruby"
    if version && architecture == "ruby"
      VERSION
    elsif version
      "#{architecture}-#{VERSION}"
    else
      "#{architecture}"
    end
  end

  def remove_gem(name, version, &block)
    @stores.each do |_, store|
      if store.gem?(name, version)
        store.remove_gem(name, version, &block)
      end
    end
  end

  def prepare(versions)
    @stores.each do |_, store|
      store.prepare(versions)
    end
  end

  def gems_for_lib(file)
    @stores.each do |_, store|
      store.gems_for_lib(file) do |gem, subdir, ext|
        yield gem, subdir, ext
      end
    end
  end

  def each(gem_name = nil, &block)
    return enum_for(__callee__, gem_name) unless block_given?

    @stores.each do |_, store|
      store.each(gem_name, &block)
    end
  end

  def gem(name, version)
    @stores.each do |_, store|
      g = store.gem(name, version)
      return g if g
    end
    nil
  end

  def gems(name_version_pairs)
    result = {}

    @stores.each do |_, store|
      result.update(store.gems(name_version_pairs)) do |_, l, r|
        l
      end
    end

    result
  end

  def gem?(name, version, platform = nil)
    @stores.any? do |key, store|
      next if platform && !key.start_with?(platform)
      store.gem?(name, version)
    end
  end

  def libs_for_gems(versions, &block)
    @stores.each do |_, store|
      store.libs_for_gems(versions, &block)
    end
  end
end
