# This file doesn't attempt to actually provide the RubyGems API.
#
# It supplies a few utility methods and classes that have become widely
# used just because they were always there.
#
# Sadly that does mean we interfere with any `defined?(::Gem)` checks --
# but the reality is there's just too much code that doesn't bother to
# check at all.

module Gem
  Version = Paperback::Support::GemVersion

  LoadError = Class.new(::LoadError)

  def self.try_activate(file)
    Paperback::Environment.resolve_gem_path(file) != file
  rescue LoadError
    false
  end

  def self.ruby
    RbConfig.ruby
  end

  def self.win_platform?
    false
  end
end

def gem(*args)
  Paperback::Environment.gem(*args)
end

def require(path)
  super Paperback::Environment.resolve_gem_path(path)
end
