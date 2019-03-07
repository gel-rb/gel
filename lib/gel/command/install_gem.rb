# frozen_string_literal: true

class Gel::Command::InstallGem < Gel::Command
  def run(command_line)
    gem_name, gem_version = command_line

    require_relative "../catalog"
    require_relative "../work_pool"

    Gel::WorkPool.new(2) do |work_pool|
      catalog = Gel::Catalog.new("https://rubygems.org", work_pool: work_pool)

      Gel::Environment.install_gem([catalog], gem_name, gem_version, output: $stderr)
    end
  end
end
