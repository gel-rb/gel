# frozen_string_literal: true

require "test_helper"

require "gel/package"
require "gel/package/installer"

class InstallTest < Minitest::Test
  def test_install_single_package
    Dir.mktmpdir do |dir|
      store = Gel::Store.new(dir)

      result = Gel::Package::Installer.new(store)
      g = Gel::Package.extract(fixture_file("rack-2.0.3.gem"), result)
      g.compile
      g.install

      g = Gel::Package.extract(fixture_file("rack-0.1.0.gem"), result)
      g.compile
      g.install

      assert File.exist?("#{dir}/gems/rack-2.0.3/SPEC")

      entries = []
      store.each do |gem|
        entries << [gem.name, gem.version]
      end

      assert_equal [
        ["rack", "0.1.0"],
        ["rack", "2.0.3"],
      ], entries.sort

      assert_equal({
        bindir: "bin",
        executables: ["rackup"],
        require_paths: ["lib"],
        dependencies: {},
      }, store.gem("rack", "0.1.0").info)
    end
  end

  def test_record_dependencies
    with_fixture_gems_installed(["hoe-3.0.0.gem"]) do |store|
      assert_equal({
        bindir: "bin",
        executables: ["sow"],
        require_paths: ["lib"],
        dependencies: {
          "rake" => [["~>", "0.8"]],
        },
      }, store.gem("hoe", "3.0.0").info)
    end
  end

  def test_mode_on_installed_files
    with_fixture_gems_installed(["rack-2.0.3.gem"]) do |store|
      assert_equal 0o644, File.stat("#{store.root}/gems/rack-2.0.3/lib/rack.rb").mode & 0o3777
      refute File.executable?("#{store.root}/gems/rack-2.0.3/lib/rack.rb")

      assert_equal 0o755, File.stat("#{store.root}/gems/rack-2.0.3/bin/rackup").mode & 0o3777
      assert File.executable?("#{store.root}/gems/rack-2.0.3/bin/rackup")
    end
  end

  def test_installing_an_extension
    skip if jruby?

    Dir.mktmpdir do |dir|
      store = Gel::Store.new(dir)
      result = Gel::Package::Installer.new(store)
      g = Gel::Package.extract(fixture_file("fast_blank-1.0.0.gem"), result)
      g.compile
      g.install

      # Files from gem
      assert File.exist?("#{dir}/gems/fast_blank-1.0.0/benchmark")
      assert File.exist?("#{dir}/gems/fast_blank-1.0.0/ext/fast_blank/extconf.rb")
      assert File.exist?("#{dir}/gems/fast_blank-1.0.0/ext/fast_blank/fast_blank.c")

      # Build artifact
      assert File.exist?("#{dir}/gems/fast_blank-1.0.0/ext/fast_blank/fast_blank.o")

      # Compiled binary
      dlext = RbConfig::CONFIG["DLEXT"]
      assert File.exist?("#{dir}/ext/fast_blank-1.0.0/fast_blank.#{dlext}")

      entries = []
      store.each do |gem|
        entries << [gem.name, gem.version]
      end

      assert_equal [
        ["fast_blank", "1.0.0"],
      ], entries.sort

      assert_equal({
        bindir: "bin",
        executables: [],
        extensions: true,
        require_paths: ["lib"],
        dependencies: {},
      }, store.gem("fast_blank", "1.0.0").info)
    end
  end

  def test_installing_a_rake_extension
    skip if jruby?

    with_fixture_gems_installed(["rake-12.3.2.gem"], multi: true) do |store|
      result = Gel::Package::Installer.new(store)
      dir = store["ruby", true].root

      g = Gel::Package.extract(fixture_file("rainbow-2.2.2.gem"), result)
      g.compile
      g.install

      # Files from gem
      assert File.exist?("#{dir}/gems/rainbow-2.2.2/ext/mkrf_conf.rb")
      assert File.exist?("#{dir}/gems/rainbow-2.2.2/lib/rainbow.rb")

      # Build artifact
      assert File.exist?("#{dir}/gems/rainbow-2.2.2/ext/Rakefile")

      # rainbow doesn't actually build anything -- its rakefile is a
      # hack for Ruby < 2 on Windows

      entries = []
      store.each do |gem|
        entries << [gem.name, gem.version]
      end

      assert_equal [
        ["rainbow", "2.2.2"],
        ["rake", "12.3.2"],
      ], entries.sort

      assert_equal({
        bindir: "bin",
        executables: [],
        extensions: true,
        require_paths: ["lib"],
        dependencies: {
          "rake" => [%w[>= 0]],
        },
      }, store.gem("rainbow", "2.2.2").info)
    end
  end
end
