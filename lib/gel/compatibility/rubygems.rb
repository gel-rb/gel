# frozen_string_literal: true

# Deprecation plan: Ship this without a warning for at least one
# version, so people with an existing `gel shell-setup`-configured shell
# don't get messages immediately after updating.
#
# After that, we'll ship the below message for at least one version,
# catching anyone whose terminal session is still alive from before the
# above, as well as anyone setting RUBYLIB manually.
#
# Finally, we can remove this file and surrounding directory entirely.

#$stderr.puts "Gel: lib/gel/compatibility/ is deprecated; please update your RUBYLIB to point to slib/, or use `gel shell-setup`. Restarting your shell may resolve this warning."
require_relative "../compatibility"
