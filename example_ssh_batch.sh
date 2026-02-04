#!/bin/bash
# example_ssh_batch.sh — Run commands on multiple SSH hosts using franlib.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/franlib.sh"

fl_require_cmd ssh

# ── Gather credentials ──────────────────────────────────────────────

fl_info "SSH batch execution example"
user=$(fl_ask "Username:")
pass=$(fl_ask_secret "Password:")

# ── Commands to run on each host ──────────────────────────────────
cmds='echo "Hello!"; pwd'

# ── Define hosts ────────────────────────────────────────────────────
# Edit this list or read from a file.

HOSTS=(
    dev7-cos01.dev.pdx10.clover.network
    dev7-cos02.dev.pdx10.clover.network
    dev7-cosbatch01.dev.pdx10.clover.network
)

fl_info "Will run '$cmds' on ${#HOSTS[@]} host(s)"
fl_confirm "Press ENTER to proceed..."

# ── Cleanup: clear password variable on exit ────────────────────────

_clear_pass() { pass=""; }
fl_cleanup_add _clear_pass

# ── Execute ─────────────────────────────────────────────────────────

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
