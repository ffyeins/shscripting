#!/bin/sh
# franlib.sh — POSIX sh helper library
# Source this file; do not execute directly.
# shellcheck disable=SC3043  # local is not POSIX but works on dash, ash, bash, FreeBSD sh

# ── 1. Source guard & terminal detection ─────────────────────────────

if [ -n "${_FL_SOURCED:-}" ]; then return 0; fi
_FL_SOURCED=1

# Colors only when stderr is a terminal
if [ -t 2 ]; then
    _FL_CYAN='\033[0;36m'
    _FL_YELLOW='\033[0;33m'
    _FL_RED='\033[0;31m'
    _FL_BOLD='\033[1m'
    _FL_RESET='\033[0m'
else
    _FL_CYAN=''
    _FL_YELLOW=''
    _FL_RED=''
    _FL_BOLD=''
    _FL_RESET=''
fi

# ── 2. Output functions ─────────────────────────────────────────────

fl_info() {
    printf '%b[INFO]%b %s\n' "$_FL_CYAN" "$_FL_RESET" "$1" >&2
}

fl_warn() {
    printf '%b[WARN]%b %s\n' "$_FL_YELLOW" "$_FL_RESET" "$1" >&2
}

fl_error() {
    printf '%b%b[ERROR]%b %s\n' "$_FL_BOLD" "$_FL_RED" "$_FL_RESET" "$1" >&2
}

fl_die() {
    fl_error "$1"
    exit "${2:-1}"
}

# ── 3. User input ───────────────────────────────────────────────────

fl_ask() {
    printf '%s ' "$1" >&2
    IFS= read -r _fl_answer
    printf '%s' "$_fl_answer"
}

fl_ask_secret() {
    local _fl_old_tty
    _fl_old_tty=$(stty -g 2>/dev/null)
    trap 'stty "$_fl_old_tty" 2>/dev/null' INT TERM
    printf '%s ' "$1" >&2
    stty -echo 2>/dev/null
    IFS= read -r _fl_answer
    stty "$_fl_old_tty" 2>/dev/null
    trap - INT TERM
    printf '\n' >&2
    printf '%s' "$_fl_answer"
}

fl_confirm() {
    local _fl_prompt _fl_default _fl_reply
    _fl_prompt="$1"
    _fl_default="${2:-}"

    case "$_fl_default" in
        [Yy]*) _fl_prompt="$_fl_prompt [Y/n]" ;;
        [Nn]*) _fl_prompt="$_fl_prompt [y/N]" ;;
        *)     _fl_prompt="$_fl_prompt [y/n]" ;;
    esac

    printf '%s ' "$_fl_prompt" >&2
    IFS= read -r _fl_reply

    case "$_fl_reply" in
        [Yy]*) return 0 ;;
        [Nn]*) return 1 ;;
        '')
            case "$_fl_default" in
                [Yy]*) return 0 ;;
                *)     return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

# ── 4. Command execution ────────────────────────────────────────────

fl_run() {
    "$@"
}

fl_run_or_die() {
    "$@" || fl_die "Command failed: $*"
}

fl_run_capture() {
    local _fl_rc
    _fl_output=$("$@" 2>&1)
    _fl_rc=$?
    printf '%s\n' "$_fl_output"
    return "$_fl_rc"
}

# ── 5. SSH password automation ──────────────────────────────────────

# Check if OpenSSH supports SSH_ASKPASS_REQUIRE (>= 8.4)
_fl_ssh_check_askpass_require() {
    local _fl_ver_str _fl_major _fl_minor
    _fl_ver_str=$(ssh -V 2>&1) || return 1
    # Extract version: "OpenSSH_8.4p1, ..." → "8.4"
    _fl_ver_str=${_fl_ver_str#*OpenSSH_}
    _fl_major=${_fl_ver_str%%.*}
    _fl_ver_str=${_fl_ver_str#*.}
    _fl_minor=${_fl_ver_str%%[^0-9]*}
    # Validate we got numbers
    case "$_fl_major$_fl_minor" in
        *[!0-9]*) return 1 ;;
    esac
    [ "$_fl_major" -gt 8 ] && return 0
    [ "$_fl_major" -eq 8 ] && [ "$_fl_minor" -ge 4 ] && return 0
    return 1
}

# Primary: SSH_ASKPASS with SSH_ASKPASS_REQUIRE=force (OpenSSH 8.4+)
_fl_ssh_via_askpass_force() {
    local _fl_host _fl_user _fl_pass _fl_cmds _fl_askpass_script _fl_rc
    _fl_host="$1"; _fl_user="$2"; _fl_pass="$3"; _fl_cmds="$4"
    _fl_askpass_script=$(fl_tempfile fl_askpass)
    printf '#!/bin/sh\nprintf "%%s" "%s"\n' "$_fl_pass" > "$_fl_askpass_script"
    chmod 700 "$_fl_askpass_script"
    _fl_rc=0
    SSH_ASKPASS="$_fl_askpass_script" SSH_ASKPASS_REQUIRE=force ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${_fl_user}@${_fl_host}" "$_fl_cmds" </dev/null || _fl_rc=$?
    rm -f "$_fl_askpass_script"
    return "$_fl_rc"
}

# Fallback for older Linux: SSH_ASKPASS + setsid (detaches tty)
_fl_ssh_via_askpass_setsid() {
    local _fl_host _fl_user _fl_pass _fl_cmds _fl_askpass_script _fl_rc
    _fl_host="$1"; _fl_user="$2"; _fl_pass="$3"; _fl_cmds="$4"
    _fl_askpass_script=$(fl_tempfile fl_askpass)
    printf '#!/bin/sh\nprintf "%%s" "%s"\n' "$_fl_pass" > "$_fl_askpass_script"
    chmod 700 "$_fl_askpass_script"
    _fl_rc=0
    SSH_ASKPASS="$_fl_askpass_script" DISPLAY=:0 setsid ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${_fl_user}@${_fl_host}" "$_fl_cmds" </dev/null || _fl_rc=$?
    rm -f "$_fl_askpass_script"
    return "$_fl_rc"
}

# Last resort: sshpass (if installed)
_fl_ssh_via_sshpass() {
    local _fl_host _fl_user _fl_pass _fl_cmds
    _fl_host="$1"; _fl_user="$2"; _fl_pass="$3"; _fl_cmds="$4"
    SSHPASS="$_fl_pass" sshpass -e ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${_fl_user}@${_fl_host}" "$_fl_cmds"
}

fl_ssh_run() {
    local _fl_host _fl_user _fl_pass _fl_cmds
    _fl_host="$1"; _fl_user="$2"; _fl_pass="$3"; _fl_cmds="$4"

    # 1. SSH_ASKPASS_REQUIRE=force (OpenSSH 8.4+, zero dependencies)
    if _fl_ssh_check_askpass_require; then
        _fl_ssh_via_askpass_force "$_fl_host" "$_fl_user" "$_fl_pass" "$_fl_cmds"
        return $?
    fi

    # 2. SSH_ASKPASS + setsid (older Linux)
    if fl_is_command setsid; then
        fl_warn "OpenSSH < 8.4; using setsid SSH_ASKPASS fallback"
        _fl_ssh_via_askpass_setsid "$_fl_host" "$_fl_user" "$_fl_pass" "$_fl_cmds"
        return $?
    fi

    # 3. sshpass (if available)
    if fl_is_command sshpass; then
        _fl_ssh_via_sshpass "$_fl_host" "$_fl_user" "$_fl_pass" "$_fl_cmds"
        return $?
    fi

    # 4. No method available
    fl_error "Cannot automate SSH password authentication"
    fl_error "Requires one of:"
    fl_error "  - OpenSSH >= 8.4 (for SSH_ASKPASS_REQUIRE)"
    fl_error "  - setsid command (Linux)"
    fl_error "  - sshpass: apt install sshpass / brew install hudochenkov/sshpass/sshpass"
    return 1
}

# ── 6. Utilities ────────────────────────────────────────────────────

fl_is_command() {
    command -v "$1" >/dev/null 2>&1
}

fl_require_cmd() {
    local _fl_cmd _fl_hint
    _fl_cmd="$1"
    _fl_hint="${2:-}"
    if ! fl_is_command "$_fl_cmd"; then
        if [ -n "$_fl_hint" ]; then
            fl_die "'$_fl_cmd' not found. Install: $_fl_hint"
        else
            fl_die "'$_fl_cmd' not found"
        fi
    fi
}

fl_tempfile() {
    local _fl_prefix
    _fl_prefix="${1:-franlib}"
    mktemp "/tmp/${_fl_prefix}.XXXXXX"
}

# ── 7. Cleanup framework ────────────────────────────────────────────

_FL_CLEANUP_HANDLERS=""

fl_cleanup_add() {
    if [ -z "$_FL_CLEANUP_HANDLERS" ]; then
        _FL_CLEANUP_HANDLERS="$1"
    else
        _FL_CLEANUP_HANDLERS="$_FL_CLEANUP_HANDLERS
$1"
    fi
}

_fl_run_cleanup() {
    local _fl_handler
    # Process in reverse order (LIFO)
    _fl_reversed=""
    _fl_rest="$_FL_CLEANUP_HANDLERS"
    while [ -n "$_fl_rest" ]; do
        _fl_handler="${_fl_rest%%
*}"
        if [ "$_fl_handler" = "$_fl_rest" ]; then
            _fl_rest=""
        else
            _fl_rest="${_fl_rest#*
}"
        fi
        if [ -z "$_fl_reversed" ]; then
            _fl_reversed="$_fl_handler"
        else
            _fl_reversed="$_fl_handler
$_fl_reversed"
        fi
    done

    _fl_rest="$_fl_reversed"
    while [ -n "$_fl_rest" ]; do
        _fl_handler="${_fl_rest%%
*}"
        if [ "$_fl_handler" = "$_fl_rest" ]; then
            _fl_rest=""
        else
            _fl_rest="${_fl_rest#*
}"
        fi
        [ -n "$_fl_handler" ] && "$_fl_handler"
    done
}

trap '_fl_run_cleanup' EXIT
