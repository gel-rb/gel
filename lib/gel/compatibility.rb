# frozen_string_literal: true

$:[0, 0] = File.expand_path("compatibility", __dir__)
require_relative "compatibility/rubygems"
