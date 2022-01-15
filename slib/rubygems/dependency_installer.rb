class Gem::DependencyInstaller
  def install(name, requirement = nil)
    require_relative "../../lib/gel/catalog"
    require_relative "../../lib/gel/work_pool"

    Gel::WorkPool.new(2) do |work_pool|
      catalog = Gel::Catalog.new("https://rubygems.org", work_pool: work_pool)

      return Gel::Environment.install_gem([catalog], name, requirement)
    end
  end
end
