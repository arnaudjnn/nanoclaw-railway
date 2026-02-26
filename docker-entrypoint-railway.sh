#!/bin/bash
# Railway entrypoint: fix volume permissions and drop to non-root user
# The /data volume may be root-owned on first mount, so we fix ownership
# before starting the app as the node user.
# claude-code refuses --dangerously-skip-permissions when running as root.

set -e

# Fix ownership of the data volume (runs as root)
chown -R node:node /data 2>/dev/null || true

# Drop to node user and exec the CMD
exec gosu node "$@"
