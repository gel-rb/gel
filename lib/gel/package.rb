# frozen_string_literal: true

module Gel
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

      def architecture
        @inner.architecture
      end

      def platform
        @inner.platform
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

      def required_ruby_version
        @inner.required_ruby_version&.requirements&.map { |pair| pair.map(&:to_s) }
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
  end
end
