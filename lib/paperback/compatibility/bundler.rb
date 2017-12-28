# frozen_string_literal: true

module Bundler
  def self.setup
    Paperback::Environment.activate(output: $stderr)
  end

  def self.require(*groups)
    Paperback::Environment.require_groups(*groups)
  end
end
