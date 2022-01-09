# frozen_string_literal: true

Automatiek::RakeTask.new("ruby-digest") do |lib|
  lib.version = "master"
  lib.download = { :github => "https://github.com/Solistra/ruby-digest" }
  lib.namespace = "RubyDigest"
  lib.prefix = "Gel::Vendor"
  lib.vendor_lib = "vendor/ruby-digest"
  lib.license_path = "UNLICENSE"
  lib.patch = lambda do |_filename, contents|
    # After the main class, it installs itself as a ::Digest alias, and
    # defines the pseudo-autoload global method. We don't need those.
    contents.gsub!(/^end$(?m:.*)/, "end\n")
  end
end

Automatiek::RakeTask.new("pub_grub") do |lib|
  lib.version = "master"
  lib.download = { :github => "https://github.com/jhawthorn/pub_grub" }
  lib.namespace = "PubGrub"
  lib.prefix = "Gel::Vendor"
  lib.vendor_lib = "vendor/pub_grub"
  lib.license_path = "LICENSE.txt"
end
