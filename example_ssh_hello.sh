#!/bin/bash
# example_ssh_hello.sh — Connect to hosts and run greeting commands
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/franlib.sh"

fl_require_cmd ssh

# ── Define hosts ───────────────────────────────────────────────────

HOSTS=(
    host1.example.com
    host2.example.com
    host3.example.com
)

# ── Gather credentials ────────────────────────────────────────────

fl_info "SSH hello example"
user=$(fl_ask "Username:")
pass=$(fl_ask_secret "Password:")

# ── Commands to run on each host ──────────────────────────────────

cmds='echo "Hello!"; pwd'

# ── Cleanup: clear password variable on exit ──────────────────────

_clear_pass() { pass=""; }
fl_cleanup_add _clear_pass

# ── Execute ───────────────────────────────────────────────────────

failed=0
for host in "${HOSTS[@]}"; do
    fl_info "Connecting to $host ..."
    if fl_ssh_run "$host" "$user" "$pass" "$cmds"; then
        fl_info "$host — done"
    else
        fl_error "$host — command failed (exit $?)"
        failed=$((failed + 1))
    fi
done

if [[ "$failed" -gt 0 ]]; then
    fl_warn "$failed host(s) had failures"
    exit 1
fi

fl_info "All hosts completed successfully"
