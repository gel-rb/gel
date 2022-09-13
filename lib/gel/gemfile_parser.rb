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

  def self.inline(&block)
    filename, _lineno = block.source_location

    result = GemfileContent.new(filename)
    context = ParseContext.new(result, filename)
    context.instance_eval(&block)
    result
  end

  class RunningRuby
    def self.version
      RUBY_VERSION
    end

    def self.engine
      RUBY_ENGINE
    end

    def self.engine_version
      RUBY_ENGINE_VERSION
    end
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

    def ruby(*versions, engine: nil, engine_version: nil)
      req = Gel::Support::GemRequirement.new(versions)
      running_ruby_version = RunningRuby.version
      running_engine = RunningRuby.engine
      running_engine_version = RunningRuby.engine_version

      unless req.satisfied_by?(Gel::Support::GemVersion.new(running_ruby_version))
        raise Gel::Error::MismatchRubyVersionError.new(
          running: running_ruby_version,
          requested: versions,
        )
      end
      unless !engine || running_engine == engine
        raise Gel::Error::MismatchRubyEngineError.new(
          running: running_engine,
          engine: engine,
        )
      end
      if engine_version
        raise "Cannot specify :engine_version without :engine" unless engine
        req = Gel::Support::GemRequirement.new(engine_version)
        raise "Running ruby engine version #{running_engine_version} does not match requested #{engine_version.inspect}" unless req.satisfied_by?(Gel::Support::GemVersion.new(running_engine_version))
      end
      @result.ruby << [versions, engine: engine, engine_version: engine_version]
    end

    def gem(name, *requirements, **options)
      aliases = GemfileContent::OPTION_ALIASES
      options.keys.each do |key|
        if original = aliases[key]
          raise "Duplicate key #{key.inspect} == #{original.inspect}" if options.key?(original)
          options[original] = options.delete(key)
        end
      end
      options = @result.flatten(options, @stack)
      @result.add_gem(name, requirements, options)
    end

    def gemspec(name: nil, path: ".", development_group: :development)
      dirname = File.expand_path(path, File.dirname(@result.filename))
      gemspecs = Dir[File.join(dirname, "*.gemspec")]
      gemspecs.map! { |file| Gel::GemspecParser.parse(File.read(file), file) }
      gemspecs.select! { |s| s.name == name } if name
      if gemspecs.empty?
        raise "No gemspecs at #{dirname}"
      elsif gemspecs.count > 1
        raise "Multiple gemspecs at #{dirname}"
      else
        spec = gemspecs[0]
        gem spec.name, path: path
        spec.development_dependencies.each do |dep_name, constraints|
          gem dep_name, constraints, group: development_group
        end
      end
    end

    def group(*names)
      @stack << { group: names }
      yield
    ensure
      @stack.pop
    end

    def install_if(*conditions)
      @stack << { install_if: conditions }
      yield
    ensure
      @stack.pop
    end

    def path(*names)
      @stack << { path: names }
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
    OPTION_ALIASES = {
      platform: :platforms,
    }

    attr_reader :filename

    attr_reader :sources
    attr_reader :git_sources
    attr_reader :ruby

    attr_reader :gems

    def initialize(filename)
      @filename = filename
      @sources = []
      @git_sources = {
        github: lambda do |value|
          value = value.to_s
          value = "#{value}/#{value}" unless value.include?("/")
          value += ".git" unless value.end_with?(".git")
          "https://github.com/#{value}"
        end
      }
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

      if options[:install_if]
        options[:install_if] = Array(options[:install_if]).all? do |condition|
          condition.respond_to?(:call) ? condition.call : condition
        end
      end

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

    def gem_names
      @gems.map(&:first).flatten.map(&:to_s)
    end
  end
end
