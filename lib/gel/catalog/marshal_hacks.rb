# frozen_string_literal: true

module Gem; end unless defined? Gem

class Gem::Specification
  class Unmarshalled
    attr_accessor :required_ruby_version
    attr_accessor :dependencies
  end

  def self._load(str)
    array = Marshal.load(str)
    o = Unmarshalled.new
    o.required_ruby_version = array[6].as_list
    o.dependencies = array[9].map { |d| [d.name, d.requirement.as_list] if d.type == :runtime }.compact
    o
  end
end
