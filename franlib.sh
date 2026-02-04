#!/bin/bash
# franlib.sh — bash helper library
# Source this file; do not execute directly.

# ── 1. Source guard & terminal detection ─────────────────────────────

if [[ -n "${_FL_SOURCED:-}" ]]; then return 0; fi
_FL_SOURCED=1

# Colors only when stderr is a terminal
if [[ -t 2 ]]; then
    _FL_CYAN='\033[0;36m'
    _FL_YELLOW='\033[0;33m'
    _FL_RED='\033[0;31m'
    _FL_GREEN='\033[0;32m'
    _FL_BOLD='\033[1m'
    _FL_RESET='\033[0m'
else
    _FL_CYAN=''
    _FL_YELLOW=''
    _FL_RED=''
    _FL_GREEN=''
    _FL_BOLD=''
    _FL_RESET=''
fi

# ── 2. Output functions ─────────────────────────────────────────────

fl_info() {
    printf '%b[INFO]%b %s\n' "$_FL_CYAN" "$_FL_RESET" "$1" >&2
}

fl_warn() {
    printf '%b[WARN] %s%b\n' "$_FL_YELLOW" "$1" "$_FL_RESET" >&2
}

fl_error() {
    printf '%b%b[ERROR] %s%b\n' "$_FL_BOLD" "$_FL_RED" "$1" "$_FL_RESET" >&2
}

fl_success() {
    printf '%b[SUCCESS] %s%b\n' "$_FL_GREEN" "$1" "$_FL_RESET" >&2
}

fl_print_command() {
    printf '%b[COMMAND]%b %s\n' "$_FL_CYAN" "$_FL_RESET" " $ $1" >&2
}

fl_die() {
    fl_error "$1"
    exit "${2:-1}"
}

# ── 3. User input ───────────────────────────────────────────────────

fl_ask() {
    local _fl_answer
    printf '%s ' "$1" >&2
    IFS= read -r _fl_answer
    printf '%s' "$_fl_answer"
}

fl_ask_secret() {
    local _fl_answer
    printf '%s ' "$1" >&2
    IFS= read -r -s _fl_answer
    printf '\n' >&2
    printf '%s' "$_fl_answer"
}

fl_confirm() {
    local _fl_prompt _fl_reply
    _fl_prompt="${1:-Press ENTER to continue...}"
    printf '%s ' "$_fl_prompt" >&2
    IFS= read -r _fl_reply
    return 0
}

# ── 4. Command execution ────────────────────────────────────────────

fl_run() {
    fl_print_command "$*"
    "$@"
}

fl_run_or_die() {
    fl_run "$@" || fl_die "Command failed: $*"
}

fl_run_capture() {
    local _fl_rc=0 _fl_output
    _fl_output=$(fl_run "$@" 2>&1) || _fl_rc=$?
    printf '%s\n' "$_fl_output"
    return "$_fl_rc"
}

# ── 5. SSH password automation ──────────────────────────────────────

_FL_SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

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
    [[ "$_fl_major$_fl_minor" =~ ^[0-9]+$ ]] || return 1
    (( _fl_major > 8 || (_fl_major == 8 && _fl_minor >= 4) ))
}

# Create a temporary askpass script that echoes the given password.
# Prints the script path to stdout. Caller must rm -f when done.
_fl_ssh_make_askpass() {
    local _fl_pass="$1" _fl_script _fl_escaped
    _fl_script=$(fl_tempfile fl_askpass)
    # Single-quote the password, escaping any embedded single quotes
    _fl_escaped=${_fl_pass//\'/\'\\\'\'}
    printf "#!/bin/sh\\nprintf '%%s' '%s'\\n" "$_fl_escaped" > "$_fl_script"
    chmod 700 "$_fl_script"
    printf '%s' "$_fl_script"
}

# Primary: SSH_ASKPASS with SSH_ASKPASS_REQUIRE=force (OpenSSH 8.4+)
_fl_ssh_via_askpass_force() {
    local _fl_host _fl_user _fl_pass _fl_cmds _fl_askpass_script _fl_rc
    _fl_host="$1"; _fl_user="$2"; _fl_pass="$3"; _fl_cmds="$4"
    _fl_askpass_script=$(_fl_ssh_make_askpass "$_fl_pass")
    _fl_rc=0
    SSH_ASKPASS="$_fl_askpass_script" SSH_ASKPASS_REQUIRE=force ssh \
        "${_FL_SSH_OPTS[@]}" \
        "${_fl_user}@${_fl_host}" "$_fl_cmds" </dev/null || _fl_rc=$?
    rm -f "$_fl_askpass_script"
    return "$_fl_rc"
}

# Fallback for older Linux: SSH_ASKPASS + setsid (detaches tty)
_fl_ssh_via_askpass_setsid() {
    local _fl_host _fl_user _fl_pass _fl_cmds _fl_askpass_script _fl_rc
    _fl_host="$1"; _fl_user="$2"; _fl_pass="$3"; _fl_cmds="$4"
    _fl_askpass_script=$(_fl_ssh_make_askpass "$_fl_pass")
    _fl_rc=0
    SSH_ASKPASS="$_fl_askpass_script" DISPLAY=:0 setsid ssh \
        "${_FL_SSH_OPTS[@]}" \
        "${_fl_user}@${_fl_host}" "$_fl_cmds" </dev/null || _fl_rc=$?
    rm -f "$_fl_askpass_script"
    return "$_fl_rc"
}

# Last resort: sshpass (if installed)
_fl_ssh_via_sshpass() {
    local _fl_host _fl_user _fl_pass _fl_cmds
    _fl_host="$1"; _fl_user="$2"; _fl_pass="$3"; _fl_cmds="$4"
    SSHPASS="$_fl_pass" sshpass -e ssh \
        "${_FL_SSH_OPTS[@]}" \
        "${_fl_user}@${_fl_host}" "$_fl_cmds"
}

fl_ssh_run() {
    local _fl_host _fl_user _fl_pass _fl_cmds
    _fl_host="$1"; _fl_user="$2"; _fl_pass="$3"; _fl_cmds="$4"

    fl_print_command "ssh ${_fl_user}@${_fl_host} '${_fl_cmds}'"

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
        if [[ -n "$_fl_hint" ]]; then
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

_FL_CLEANUP_HANDLERS=()

fl_cleanup_add() {
    _FL_CLEANUP_HANDLERS+=("$1")
}

_fl_run_cleanup() {
    local _fl_i
    # Process in reverse order (LIFO)
    for (( _fl_i=${#_FL_CLEANUP_HANDLERS[@]}-1; _fl_i>=0; _fl_i-- )); do
        "${_FL_CLEANUP_HANDLERS[$_fl_i]}"
    done
}

trap '_fl_run_cleanup' EXIT
