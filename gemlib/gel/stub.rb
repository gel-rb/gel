# frozen_string_literal: true

# This file exists to be required from a Gel binstub if it has been
# loaded via 'ruby -S' and Rubygems was loaded. It (only) defines an
# alternative implementation of Gel.stub, which will re-exec Ruby to
# switch to Gel.

module Gel
  def self.stub(name)
    # Note there's a similar re-exec in exe/gel

    exec ::Gem.ruby,
      "-I", File.expand_path("../slib", __dir__),
      "--",
      File.expand_path("../exe/gel", __dir__),
      "stub",
      name,
      *ARGV
  end
end
