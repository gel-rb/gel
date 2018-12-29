# frozen_string_literal: true

class Gem::Dependency
  attr_accessor :name, :type, :requirement
end

class Gem::Specification
  attr_accessor :required_ruby_version
  attr_accessor :dependencies

  def self._load(str)
    array = Marshal.load(str)
    o = new
    o.required_ruby_version = array[6].as_list
    o.dependencies = array[9].map { |d| [d.name, d.requirement.as_list] if d.type == :runtime }.compact
    o
  end
end
