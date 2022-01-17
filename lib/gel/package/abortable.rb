# frozen_string_literal: true

module Kernel
  module_function

  alias_method :abort_without_gel, :abort
  singleton_class.undef_method :abort

  def abort(message = nil)
    IO.open(3, "w") { |f| f.write(message) }
    abort_without_gel(message)
  end
  private :abort
end

class << Process
  public :abort
end
