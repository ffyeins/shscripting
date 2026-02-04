#!/bin/bash
# test_franlib.sh — Tests for franlib.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/franlib.sh"

_pass=0
_fail=0

assert_eq() {
    local _label _got _want
    _label="$1"; _got="$2"; _want="$3"
    if [[ "$_got" = "$_want" ]]; then
        fl_info "PASS: $_label"
        _pass=$((_pass + 1))
    else
        fl_error "FAIL: $_label (got '$_got', want '$_want')"
        _fail=$((_fail + 1))
    fi
}

assert_rc() {
    local _label _want_rc _cmd
    _label="$1"; _want_rc="$2"; shift 2
    _got_rc=0
    "$@" || _got_rc=$?
    if [[ "$_got_rc" -eq "$_want_rc" ]]; then
        fl_info "PASS: $_label"
        _pass=$((_pass + 1))
    else
        fl_error "FAIL: $_label (exit $_got_rc, want $_want_rc)"
        _fail=$((_fail + 1))
    fi
}

# ── Source guard ─────────────────────────────────────────────────────

assert_eq "source guard set" "$_FL_SOURCED" "1"

# ── Output functions ─────────────────────────────────────────────────

fl_info "Testing fl_info — you should see this"
fl_warn "Testing fl_warn — you should see this"
fl_error "Testing fl_error — you should see this"
fl_info "(fl_die not tested directly — it would exit the script)"

# ── fl_is_command / fl_require_cmd ───────────────────────────────────

assert_rc "fl_is_command sh" 0 fl_is_command sh
assert_rc "fl_is_command nonexistent_xyz" 1 fl_is_command nonexistent_xyz

# fl_require_cmd for an existing command should not die
fl_require_cmd sh
fl_info "PASS: fl_require_cmd sh (did not die)"
_pass=$((_pass + 1))

# fl_require_cmd for missing command — run in subshell to catch exit
_rc=0
(fl_require_cmd nonexistent_xyz "some hint" 2>/dev/null) || _rc=$?
assert_eq "fl_require_cmd dies for missing cmd" "$([[ "$_rc" -ne 0 ]] && echo yes)" "yes"

# ── fl_run / fl_run_or_die / fl_run_capture ─────────────────────────

out=$(fl_run echo hello)
assert_eq "fl_run echo" "$out" "hello"

out=$(fl_run_capture echo "capture this")
# fl_run_capture merges stderr (including the [COMMAND] log) into stdout
assert_eq "fl_run_capture echo" "$([[ "$out" == *"capture this"* ]] && echo yes)" "yes"

assert_rc "fl_run_or_die true" 0 fl_run_or_die true

_rc=0
(fl_run_or_die false 2>/dev/null) || _rc=$?
assert_eq "fl_run_or_die false dies" "$([[ "$_rc" -ne 0 ]] && echo yes)" "yes"

# fl_run_or_die logs the command via fl_run
_stderr=$(fl_run_or_die echo hi 2>&1 >/dev/null)
assert_eq "fl_run_or_die logs command" "$([[ "$_stderr" == *"[COMMAND]"*"echo hi"* ]] && echo yes)" "yes"

# fl_run_capture logs the command via fl_run
_stderr=$(fl_run_capture echo hi 2>/dev/null; true)  # capture stdout, but stderr went to /dev/null
# Run again, capturing stderr this time
_both=$(fl_run_capture echo hi 2>&1)
assert_eq "fl_run_capture logs command" "$([[ "$_both" == *"[COMMAND]"*"echo hi"* ]] && echo yes)" "yes"

# ── fl_tempfile ──────────────────────────────────────────────────────

tmp=$(fl_tempfile testfl)
assert_eq "fl_tempfile creates file" "$([[ -f "$tmp" ]] && echo yes)" "yes"
rm -f "$tmp"

# ── cleanup framework ───────────────────────────────────────────────

_test_cleanup_ran=""
_test_cleanup_fn() { _test_cleanup_ran="yes"; }
fl_cleanup_add _test_cleanup_fn

# Cleanup will fire on EXIT; test in a subshell
_out=$( (
    _FL_SOURCED=""
    . "$SCRIPT_DIR/franlib.sh" 2>/dev/null
    _sub_marker=""
    _sub_cleanup() { _sub_marker="cleaned"; printf '%s' "$_sub_marker"; }
    fl_cleanup_add _sub_cleanup
    exit 0
) )
assert_eq "cleanup runs on exit" "$_out" "cleaned"

# ── fl_confirm (non-interactive, pipe in answer) ────────────────────

_rc=0
printf 'y\n' | fl_confirm "test?" 2>/dev/null || _rc=$?
assert_eq "fl_confirm y" "$_rc" "0"

_rc=0
printf 'n\n' | fl_confirm "test?" 2>/dev/null || _rc=$?
assert_eq "fl_confirm n" "$_rc" "1"

_rc=0
printf '\n' | fl_confirm "test?" "y" 2>/dev/null || _rc=$?
assert_eq "fl_confirm default=y, empty" "$_rc" "0"

_rc=0
printf '\n' | fl_confirm "test?" "n" 2>/dev/null || _rc=$?
assert_eq "fl_confirm default=n, empty" "$_rc" "1"

# ── fl_ask (non-interactive) ────────────────────────────────────────

out=$(printf 'hello world\n' | fl_ask "prompt:" 2>/dev/null)
assert_eq "fl_ask reads input" "$out" "hello world"

# ── _fl_ssh_check_askpass_require (version parsing) ─────────────────

# Test by mocking ssh -V output via a wrapper script
_fl_test_version_check() {
    local _ver_string _expect _label _mock_ssh _mock_dir _rc
    _ver_string="$1"; _expect="$2"; _label="$3"

    _mock_dir=$(fl_tempfile fl_mockdir)
    rm -f "$_mock_dir"
    mkdir "$_mock_dir"
    _mock_ssh="$_mock_dir/ssh"
    printf '#!/bin/sh\nprintf "%%s\\n" "%s" >&2\n' "$_ver_string" > "$_mock_ssh"
    chmod 755 "$_mock_ssh"

    _rc=0
    PATH="$_mock_dir:$PATH" _fl_ssh_check_askpass_require || _rc=$?

    rm -rf "$_mock_dir"

    if [[ "$_expect" = "0" ]]; then
        assert_eq "$_label" "$_rc" "0"
    else
        assert_eq "$_label" "$([[ "$_rc" -ne 0 ]] && echo fail)" "fail"
    fi
}

_fl_test_version_check "OpenSSH_8.4p1, OpenSSL 1.1.1" 0 "ssh version 8.4 >= 8.4"
_fl_test_version_check "OpenSSH_9.2p1 Debian-2" 0 "ssh version 9.2 >= 8.4"
_fl_test_version_check "OpenSSH_8.3p1, OpenSSL 1.1.1" 1 "ssh version 8.3 < 8.4"
_fl_test_version_check "OpenSSH_7.9p1" 1 "ssh version 7.9 < 8.4"
_fl_test_version_check "OpenSSH_10.0p1" 0 "ssh version 10.0 >= 8.4"

# ── fl_ssh_run logs the command ──────────────────────────────────────

# fl_ssh_run should log a [COMMAND] line with user@host before attempting SSH.
# We run it in a subshell and expect it to fail (no actual SSH server), but the
# log line should still appear on stderr.
_stderr=$( (fl_ssh_run "testhost" "testuser" "testpass" "uptime" 2>&1 >/dev/null) 2>&1 || true )
assert_eq "fl_ssh_run logs command" \
    "$([[ "$_stderr" == *"[COMMAND]"*"ssh testuser@testhost"*"uptime"* ]] && echo yes)" "yes"

# ── _fl_ssh_make_askpass (password escaping) ─────────────────────────

_askpass_script=$(_fl_ssh_make_askpass "simple")
_askpass_out=$(sh "$_askpass_script")
rm -f "$_askpass_script"
assert_eq "askpass simple password" "$_askpass_out" "simple"

_askpass_script=$(_fl_ssh_make_askpass "it's a \"test\" \$HOME")
_askpass_out=$(sh "$_askpass_script")
rm -f "$_askpass_script"
assert_eq "askpass special chars" "$_askpass_out" "it's a \"test\" \$HOME"

# ── Summary ──────────────────────────────────────────────────────────

printf '\n' >&2
fl_info "Results: $_pass passed, $_fail failed"
if [[ "$_fail" -gt 0 ]]; then
    fl_error "Some tests failed"
    exit 1
fi
fl_info "All tests passed"
