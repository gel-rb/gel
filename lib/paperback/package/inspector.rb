# frozen_string_literal: true

module Paperback
  class Package
    class Inspector
      def initialize(&block)
        @block = block
      end

      attr_reader :spec

      def gem(spec)
        @spec = spec

        yield self if @block
      end

      def file(filename, io, _mode)
        @block.call filename, io
      end
    end
  end
end
