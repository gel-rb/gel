# frozen_string_literal: true

require "zlib"
require "yaml"

require_relative "../support/sha512"
require_relative "../support/tar"
require_relative "../vendor/ruby_digest"

require_relative "yaml_loader"

module Gel
  class Package
    module Extracter
      def self.with_file(reader, filename, checksums)
        reader.seek(filename) do |stream|
          if checksums
            data = stream.read
            stream.rewind

            checksums.each do |type, map|
              calculated =
                case type
                when "SHA1"
                  Gel::Vendor::RubyDigest::SHA1.hexdigest(data)
                when "SHA512"
                  Gel::Support::SHA512.hexdigest(data)
                else
                  next
                end
              raise "#{type} checksum mismatch on #{filename}" unless calculated == map[filename]
            end
          end

          yield stream
        end
      end

      def self.extract(filename, receiver)
        File.open(filename) do |io|
          Gel::Support::Tar::TarReader.new(io) do |package_reader|
            sums = with_file(package_reader, "checksums.yaml.gz", nil) do |sum_stream|
              yaml = Zlib::GzipReader.new(sum_stream).read

              if Psych::VERSION < "3.1" # Ruby 2.5 & below
                ::YAML.safe_load(yaml, [], [], false, "#{filename}:checksums.yaml.gz")
              else
                ::YAML.safe_load(yaml, filename: "#{filename}:checksums.yaml.gz")
              end
            end

            spec = with_file(package_reader, "metadata.gz", sums) do |meta_stream|
              yaml = Zlib::GzipReader.new(meta_stream).read
              loaded = YAMLLoader.load(yaml, "#{filename}:metadata.gz")
              Specification.new(loaded)
            end or raise "no metadata.gz"

            return receiver.gem(spec) do |target|
              with_file(package_reader, "data.tar.gz", sums) do |data_stream|
                Gel::Support::Tar::TarReader.new(Zlib::GzipReader.new(data_stream)) do |data_reader|
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
end
