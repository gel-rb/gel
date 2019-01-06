# frozen_string_literal: true

class Paperback::Command::InstallGem < Paperback::Command
  def run(command_line)
    gem_name, gem_version = command_line

    require_relative "../catalog"
    require_relative "../work_pool"

    Paperback::WorkPool.new(2) do |work_pool|
      catalog = Paperback::Catalog.new("https://rubygems.org", work_pool: work_pool)

      Paperback::Environment.install_gem([catalog], gem_name, gem_version, output: $stderr)
    end
  end
end
