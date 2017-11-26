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
      store.each do |name, version, info|
        entries << [name, version, info]
      end

      assert_equal [
        ["rack", "0.1.0", {}],
        ["rack", "2.0.3", {}],
      ], entries.sort

      assert_equal({ bindir: "bin", require_paths: ["lib"] }, store.gem_info("rack", "0.1.0"))
    end
  end
end
