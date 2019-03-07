require_relative "lib/gel/version"

Gem::Specification.new do |spec|
  spec.name          = "gel"
  spec.version       = Gel::VERSION
  spec.authors       = ["Gel Authors"]
  spec.email         = ["team@gel.dev"]

  spec.summary       = "A modern gem manager"
  spec.homepage      = "https://gel.dev"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "pub_grub", "0.5.0.alpha3"

  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "mocha"
  spec.add_development_dependency "webmock"
end
