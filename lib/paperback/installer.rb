class Paperback::Installer
  attr_reader :store

  def initialize(store)
    @store = store
    @queue = []
    @errors = []
  end

  def install_gem(catalogs, name, version)
    @queue << [catalogs, name, version]
    start
  end

  def start
    work(*@queue.shift)
  end

  def work(catalogs, name, version)
    catalogs.each do |catalog|
      begin
        f = catalog.download_gem(name, version)
      rescue Net::HTTPError
      else
        f.close
        installer = Paperback::Package::Installer.new(store)
        g = Paperback::Package.extract(f.path, installer)
        g.compile
        g.install
        return
      ensure
        f.unlink if f
      end
    end

    @errors << "Unable to locate #{name} #{version} in: #{catalogs.join ", "}"
  end

  def wait
    raise @errors.join("\n") unless @errors.empty?
  end
end
