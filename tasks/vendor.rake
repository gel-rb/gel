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

Automatiek::RakeTask.new("pstore") do |lib|
  lib.version = "master"
  lib.download = { :github => "https://github.com/ruby/pstore" }
  lib.namespace = "PStore"
  lib.prefix = "Gel::Vendor"
  lib.vendor_lib = "vendor/pstore"
  lib.license_path = "LICENSE.txt"
  lib.patch = lambda do |_filename, contents|
    # Use our vendored digest library
    contents.gsub!(/^require "digest"$/, %(require_relative "../../ruby-digest/lib/ruby_digest"))
    contents.gsub!(/^(\s*)CHECKSUM_ALGO = (?m:.*?)^\1end$/, "\\1CHECKSUM_ALGO = Gel::Vendor::RubyDigest::SHA256")
  end
end

Automatiek::RakeTask.new("pub_grub") do |lib|
  lib.version = "e5c69d251b3d55791b83d131ddd2b587a282778a"
  lib.download = { :github => "https://github.com/jhawthorn/pub_grub" }
  lib.namespace = "PubGrub"
  lib.prefix = "Gel::Vendor"
  lib.vendor_lib = "vendor/pub_grub"
  lib.license_path = "LICENSE.txt"
end
