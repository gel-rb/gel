# frozen_string_literal: true

class Gel::GemspecParser
  module Context
    def self.context
      binding
    end

    module Gem
      Version = Gel::Support::GemVersion
      Requirement = Gel::Support::GemRequirement

      VERSION = "2.99.0"

      module Platform
        RUBY = "ruby"
      end

      module Specification
        def self.new(name = nil, version = nil, &block)
          result = Result.new
          result.name = name
          result.version = version
          block.call result
          result
        end
      end
    end
  end

  class Result
    def initialize
      @values = {}

      self.specification_version = nil
      self.metadata = {}
      self.requirements = []
      self.rdoc_options = []
      self.extra_rdoc_files = []
      self.development_dependencies = []
      self.runtime_dependencies = []
      self.executables = []
      self.extensions = []
    end

    def add_development_dependency(name, *versions)
      development_dependencies << [name, versions.flatten]
    end

    def add_runtime_dependency(name, *versions)
      runtime_dependencies << [name, versions.flatten]
    end
    alias add_dependency add_runtime_dependency

    def method_missing(name, *args)
      if name =~ /(.*)=$/
        @values[$1.to_sym] = args.first
      else
        @values[name]
      end
    end

    def respond_to_missing?(name, *)
      name != :marshal_dump && name != :_dump
    end
  end

  def self.parse(content, filename, lineno = 1, root: File.dirname(filename), isolate: true)
    filename = File.expand_path(filename)
    root = File.expand_path(root)

    if isolate
      in_read, in_write = IO.pipe
      out_read, out_write = IO.pipe

      pid = spawn({
                    "RUBYLIB" => Gel::Environment.modified_rubylib,
                    "RUBYOPT" => "",
                    "GEL_DEBUG" => nil,
                    "GEL_GEMFILE" => "",
                    "GEL_LOCKFILE" => "",
                  },
                  RbConfig.ruby,
                  "-r", File.expand_path("compatibility", __dir__),
                  "-r", File.expand_path("gemspec_parser", __dir__),
                  "-e", "IO.new(3, 'w').write Marshal.dump(Gel::GemspecParser.parse($stdin.read, ARGV.shift, ARGV.shift.to_i, root: ARGV.shift, isolate: false))",
                  filename, lineno.to_s, root,
                  in: in_read, 3 => out_write)

      in_read.close
      out_write.close

      write_thread = Thread.new do
        in_write.write content
        in_write.close
      end

      read_thread = Thread.new do
        out_read.read
      end

      _, status = Process.waitpid2(pid)
      raise Gel::Error::ParsedGemspecError unless status.success?

      write_thread.join
      Marshal.load read_thread.value

    else
      Dir.chdir(root) do
        Context.context.eval(content, filename, lineno)
      end
    end
  end
end
