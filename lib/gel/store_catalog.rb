# frozen_string_literal: true

class Gel::StoreCatalog
  attr_reader :store

  def initialize(store)
    @store = store
    @cache = {}
  end

  def gem_info(name)
    @cache.fetch(name) { @cache[name] = _info(name) }
  end

  def _info(name)
    info = {}

    @store.each(name) do |store_gem|
      info[store_gem.version] = {
        dependencies: store_gem.dependencies.map do |dep_name, pairs|
          [dep_name, pairs.map { |op, ver| "#{op} #{ver}" }]
        end,
      }
    end

    info
  end

  def prepare
  end
end
