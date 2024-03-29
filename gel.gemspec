# frozen_string_literal: true

require_relative "lib/gel/version"

Gem::Specification.new do |spec|
  spec.name          = "gel"
  spec.version       = Gel::VERSION
  spec.authors       = ["Gel Authors"]
  spec.email         = ["team@gel.dev"]

  spec.summary       = "A modern gem manager"
  spec.homepage      = "https://gel.dev"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z exe gemlib lib slib vendor *.md *.txt`.split("\x0") +
    Dir["man/man?/*.?"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["gemlib"]

  spec.add_development_dependency "ruby-digest"
  spec.add_development_dependency "pstore"
  spec.add_development_dependency "pub_grub"
end
