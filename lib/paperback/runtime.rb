if ENV["PAPERBACK_STORE"]
  # TODO: This loads too much
  require "paperback"

  store = Paperback::Store.new(ENV["PAPERBACK_STORE"])

  if ENV["PAPERBACK_LOCKFILE"]
    Paperback::Environment::IGNORE_LIST.concat ENV["PAPERBACK_IGNORE"].split if ENV["PAPERBACK_IGNORE"]

    loader = Paperback::LockLoader.new(ENV["PAPERBACK_LOCKFILE"])

    loader.activate(Paperback::Environment, store, install: !!ENV["PAPERBACK_INSTALL"])
  end
end
