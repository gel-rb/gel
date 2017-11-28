require "test_helper"

class InstallTest < Minitest::Test
  def test_install_single_package
    Dir.mktmpdir do |dir|
      store = Paperback::Store.new(dir)
      result = Paperback::Package::Installer.new(store)
      Paperback::Package.extract(fixture_file("rack-2.0.3.gem"), result)
      Paperback::Package.extract(fixture_file("rack-0.1.0.gem"), result)

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
end
