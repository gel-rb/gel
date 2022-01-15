# We assume this file is only required by the `gem` executable: if we
# get here, we need to re-exec it without Gel on the path, to ensure it
# has a full and proper Rubygems environment to work with.

ENV["RUBYLIB"] = Gel::Environment.original_rubylib
exec RbConfig.ruby, "--", $0, *ARGV
