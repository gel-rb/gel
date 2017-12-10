require "ostruct"

class Paperback::GemspecParser
  module Context
    def self.context
      binding
    end

    module Gem
      Version = Paperback::Support::GemVersion
      Requirement = Paperback::Support::GemRequirement

      VERSION = "2.99.0"

      module Platform
        RUBY = "ruby".freeze
      end

      module Specification
        def self.new(&block)
          o = Result.new
          block.call o
          o
        end
      end
    end
  end

  class Result < OpenStruct
    def initialize
      super
      self.specification_version = nil
      self.metadata = {}
      self.requirements = []
      self.rdoc_options = []
      self.development_dependencies = []
      self.runtime_dependencies = []
    end

    def add_development_dependency(name, *versions)
      development_dependencies << [name, versions.flatten]
    end

    def add_runtime_dependency(name, *versions)
      runtime_dependencies << [name, versions.flatten]
    end
    alias add_dependency add_runtime_dependency
  end

  def self.parse(content, filename, lineno = 1, root: File.dirname(filename))
    Dir.chdir(root) do
      Context.context.eval(content, filename, lineno)
    end
  end
end
