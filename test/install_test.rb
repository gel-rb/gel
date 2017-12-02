require "test_helper"

class InstallTest < Minitest::Test
  def test_install_single_package
    Dir.mktmpdir do |dir|
      store = Paperback::Store.new(dir)

      result = Paperback::Package::Installer.new(store)
      g = Paperback::Package.extract(fixture_file("rack-2.0.3.gem"), result)
      g.compile
      g.install

      g = Paperback::Package.extract(fixture_file("rack-0.1.0.gem"), result)
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
        require_paths: ["lib"],
        dependencies: {},
      }, store.gem("rack", "0.1.0").info)
    end
  end

  def test_record_dependencies
    with_fixture_gems_installed(["hoe-3.0.0.gem"]) do |store|
      assert_equal({
        bindir: "bin",
        require_paths: ["lib"],
        dependencies: {
          "rake" => [["~>", "0.8"]],
        },
      }, store.gem("hoe", "3.0.0").info)
    end
  end

  def test_installing_an_extension
    Dir.mktmpdir do |dir|
      store = Paperback::Store.new(dir)
      result = Paperback::Package::Installer.new(store)
      g = Paperback::Package.extract(fixture_file("fast_blank-1.0.0.gem"), result)
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
        extensions: true,
        require_paths: ["lib"],
        dependencies: {},
      }, store.gem("fast_blank", "1.0.0").info)
    end
  end
end
