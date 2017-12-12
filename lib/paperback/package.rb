require "zlib"
require "yaml"

module Paperback
  class Package
    class Specification
      def initialize(inner)
        @inner = inner
      end

      def name
        @inner.name
      end

      def version
        @inner.version
      end

      def bindir
        @inner.bindir
      end

      def executables
        @inner.executables
      end

      def require_paths
        @inner.require_paths
      end

      def extensions
        @inner.extensions
      end

      def runtime_dependencies
        h = {}
        @inner.dependencies.each do |dep|
          next unless dep.type == :runtime || dep.type.nil?
          req = dep.requirement || dep.version_requirements
          h[dep.name] = req.requirements.map { |pair| pair.map(&:to_s) }
        end
        h
      end
    end

    class YAMLLoader < ::YAML::ClassLoader::Restricted
      #--
      # Based on YAML.safe_load
      def self.load(yaml, filename)
        result = ::YAML.parse(yaml, filename)
        return unless result

        class_loader = self.new
        scanner      = ::YAML::ScalarScanner.new class_loader

        visitor = ::YAML::Visitors::ToRuby.new scanner, class_loader
        visitor.accept result
      end

      def initialize
        super(%w(Symbol Time), [])
      end

      def find(klass)
        case klass
        when "Gem::Specification"
          Gem_Specification
        when "Gem::Version"
          Gem_Version
        when "Gem::Version::Requirement", "Gem::Requirement"
          Gem_Requirement
        when "Gem::Platform"
          Gem_Platform
        when "Gem::Dependency"
          Gem_Dependency
        else
          super
        end
      end

      class Gem_Specification
        attr_accessor :bindir, :executables, :name, :require_paths, :specification_version, :version, :dependencies, :extensions
      end
      class Gem_Dependency
        attr_accessor :name, :requirement, :type, :version_requirements
      end
      class Gem_Platform; end
      Gem_Version = Paperback::Support::GemVersion
      class Gem_Requirement
        attr_accessor :requirements
      end
    end

    def self.with_file(reader, filename, checksums)
      reader.seek(filename) do |stream|
        if checksums
          data = stream.read
          stream.rewind

          checksums.each do |type, map|
            next unless %w(SHA1 SHA512).include?(type)
            calculated = Digest(type).hexdigest(data)
            raise "#{type} checksum mismatch on #{filename}" unless calculated == map[filename]
          end
        end

        yield stream
      end
    end

    def self.extract(filename, receiver)
      File.open(filename) do |io|
        Paperback::Support::Tar::TarReader.new(io) do |package_reader|
          sums = with_file(package_reader, "checksums.yaml.gz", nil) do |sum_stream|
            yaml = Zlib::GzipReader.new(sum_stream).read
            ::YAML.safe_load(yaml, [], [], false, "#{filename}:checksums.yaml.gz")
          end

          spec = with_file(package_reader, "metadata.gz", sums) do |meta_stream|
            yaml = Zlib::GzipReader.new(meta_stream).read
            loaded = YAMLLoader.load(yaml, "#{filename}:metadata.gz")
            Specification.new(loaded)
          end or raise "no metadata.gz"

          return receiver.gem(spec) do |target|
            with_file(package_reader, "data.tar.gz", sums) do |data_stream|
              Paperback::Support::Tar::TarReader.new(Zlib::GzipReader.new(data_stream)) do |data_reader|
                data_reader.each do |entry|
                  target.file(entry.full_name, entry, entry.header.mode)
                end
              end
              true
            end or raise "no data.tar.gz"
          end
        end
      end
    end
  end
end
