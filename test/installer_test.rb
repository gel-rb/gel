# frozen_string_literal: true

require "test_helper"

require "gel/installer"

class InstallerTest < Minitest::Test
  def test_install_git_gems_only_checkout_once
    Dir.mktmpdir do |dir|
      remote = "https://github.com/rails/rails.git"
      revision = "d56d2e740612717334840b0d0ea979e1ca7cf5b1"
      names = ["actioncable", "actionmailbox"]
      store = Gel::Store.new(dir)
      installer = Gel::Installer.new(store)
      fake_download_pool = Minitest::Mock.new
      installer.instance_variable_set(
        :@download_pool,
        fake_download_pool
      )
      fake_download_pool.expect(:queue, true) do |argument|
        argument == "actioncable"
      end

      names.each do |name|
        installer.load_git_gem(remote, revision, name)
      end
    end
  end
end
