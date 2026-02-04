#!/bin/sh
# example_ssh_batch.sh — Run commands on multiple SSH hosts using franlib.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/franlib.sh"

fl_require_cmd ssh
fl_require_cmd sshpass "apt install sshpass / brew install hudochenkov/sshpass/sshpass"

# ── Gather credentials ──────────────────────────────────────────────

fl_info "SSH batch execution example"
user=$(fl_ask "Username:")
pass=$(fl_ask_secret "Password:")
cmds=$(fl_ask "Command to run on each host:")

# ── Define hosts ────────────────────────────────────────────────────
# Edit this list or read from a file.

HOSTS="server1.example.com
server2.example.com
server3.example.com"

fl_info "Will run '$cmds' on $(printf '%s\n' "$HOSTS" | wc -l | tr -d ' ') host(s)"
fl_confirm "Proceed?" "y" || fl_die "Aborted by user"

# ── Cleanup: clear password variable on exit ────────────────────────

_clear_pass() { pass=""; }
fl_cleanup_add _clear_pass

# ── Execute ─────────────────────────────────────────────────────────

failed=0
while IFS= read -r host; do
    [ -z "$host" ] && continue
    fl_info "Connecting to $host ..."
    if fl_ssh_run "$host" "$user" "$pass" "$cmds"; then
        fl_info "$host — done"
    else
        fl_error "$host — command failed (exit $?)"
        failed=$((failed + 1))
    fi
done <<EOF
$HOSTS
EOF

if [ "$failed" -gt 0 ]; then
    fl_warn "$failed host(s) had failures"
    exit 1
fi

fl_info "All hosts completed successfully"
