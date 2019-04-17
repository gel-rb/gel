# frozen_string_literal: true

module Gel::GemfileParser
  def self.parse(content, filename = nil, lineno = nil)
    result = GemfileContent.new(filename)
    context = ParseContext.new(result, filename)
    if filename
      context.instance_eval(content, filename, lineno)
    else
      context.instance_eval(content)
    end
    result
  rescue ScriptError, StandardError
    raise Gel::Error::GemfileEvaluationError.new(filename: filename)
  end

  class ParseContext
    def initialize(result, filename)
      @result = result

      @stack = []
    end

    def source(uri)
      if block_given?
        begin
          @stack << { source: uri }
          yield
        ensure
          @stack.pop
        end
      else
        @result.sources << uri
      end
    end

    def git_source(name, &block)
      @result.git_sources[name] = block
    end

    def ruby(version, engine: nil, engine_version: nil)
      req = Gel::Support::GemRequirement.new(version)
      raise "Running ruby version #{RUBY_VERSION} does not match requested #{version.inspect}" unless req.satisfied_by?(Gel::Support::GemVersion.new(RUBY_VERSION))
      raise "Running ruby engine #{RUBY_ENGINE} does not match requested #{engine.inspect}" unless !engine || RUBY_ENGINE == engine
      if engine_version
        raise "Cannot specify :engine_version without :engine" unless engine
        req = Gel::Support::GemRequirement.new(version)
        raise "Running ruby engine version #{RUBY_ENGINE_VERSION} does not match requested #{engine_version.inspect}" unless req.satisfied_by?(Gel::Support::GemVersion.new(RUBY_ENGINE_VERSION))
      end
      @result.ruby << [version, engine: engine, engine_version: engine_version]
    end

    def gem(name, *requirements, **options)
      options = @result.flatten(options, @stack)
      @result.add_gem(name, requirements, options)
    end

    def gemspec
      if file = Dir["#{File.dirname(@result.filename)}/*.gemspec"].first
        spec = Gel::GemspecParser.parse(File.read(file), file)
        gem spec.name, path: "."
        spec.development_dependencies.each do |name, constraints|
          gem name, constraints, group: :development
        end
      end
    end

    def group(*names)
      @stack << { group: names }
      yield
    ensure
      @stack.pop
    end

    def platforms(*names)
      @stack << { platforms: names }
      yield
    ensure
      @stack.pop
    end
  end

  class GemfileContent
    attr_reader :filename

    attr_reader :sources
    attr_reader :git_sources
    attr_reader :ruby

    attr_reader :gems

    def initialize(filename)
      @filename = filename
      @sources = []
      @git_sources = {}
      @ruby = []
      @gems = []
    end

    def flatten(options, stack)
      options = options.dup
      stack.reverse_each do |layer|
        options.update(layer) { |_, current, outer| current }
      end
      @git_sources.each do |key, block|
        next unless options.key?(key)
        raise "Multiple git sources specified" if options.key?(:git)
        options[:git] = block.call(options.delete(key))
      end
      options
    end

    def add_gem(name, requirements, options)
      return if name == "bundler"
      raise "Only git sources can specify a :branch" if options[:branch] && !options[:git]
      raise "Duplicate entry for gem #{name.inspect}" if @gems.assoc(name)

      @gems << [name, requirements, options]
    end

    def autorequire(target, gems = self.gems)
      gems.each do |name, _version, options|
        next if options[:require] == false

        if [nil, true].include?(options[:require])
          alt_name = name.include?("-") && name.tr("-", "/")
          if target.gem_has_file?(name, name)
            target.scoped_require name, name
          elsif alt_name && target.gem_has_file?(name, alt_name)
            target.scoped_require name, alt_name
          elsif options[:require] == true
            target.scoped_require name, name
          end
        elsif options[:require].is_a?(Array)
          options[:require].each do |path|
            target.scoped_require name, path
          end
        else
          target.scoped_require name, options[:require]
        end
      end
    end
  end
end
