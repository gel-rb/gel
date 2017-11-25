module Paperback::Support
  module Tar
    class Error < ::RuntimeError; end

    class NonSeekableIO < Error; end
    class TooLongFileName < Error; end
    class TarInvalidError < Error; end
  end
end

require_relative "tar/tar_header"
require_relative "tar/tar_reader"
require_relative "tar/tar_writer"
