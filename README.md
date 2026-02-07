# franlib.sh

A bash helper library for colored output, user input, command execution, SSH automation, and cleanup handling.

Requires bash 3.2+ (the version shipped with macOS). No external dependencies.

## Getting started

Source the library at the top of your script:

```bash
#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/franlib.sh"
```

## Output

```bash
fl_info "Deployment started"        # [ INFO ] Deployment started
fl_warn "Disk usage above 80%"      # [ WARN ] Disk usage above 80%
fl_error "Connection refused"       # [ ERROR ] Connection refused
fl_ok "All checks passed"           # [ OK ] All checks passed
```

Colors are enabled automatically when stderr is a terminal, and disabled otherwise.

## User input

```bash
name=$(fl_ask "What is your name?")
fl_info "Hello, $name"

pass=$(fl_ask_secret "Password:")
# Input is hidden while typing

fl_confirm                              # Press ENTER to continue...
fl_confirm "Ready to deploy?"           # Ready to deploy?
```

## Command execution

`fl_run` logs every command to stderr before executing it, so you can always see what ran:

```bash
fl_run mkdir -p /tmp/backups
# [ CMD ]  $ mkdir -p /tmp/backups

fl_run_or_die tar czf backup.tar.gz /data
# Exits the script if the command fails

output=$(fl_run_capture ls /etc)
# Captures stdout+stderr into a variable while still logging the command
```

## Checking for commands

```bash
if fl_is_command docker; then
    fl_info "Docker is installed"
fi

fl_require_cmd curl
# Exits with an error if curl is not found
```

## Temp files

```bash
tmpfile=$(fl_tempfile myprefix)
# Creates /tmp/myprefix.XXXXXX
```

## Cleanup

Register functions that run automatically when your script exits (processed in LIFO order):

```bash
_my_cleanup() {
    rm -f "$tmpfile"
}
fl_cleanup_add _my_cleanup

# When the script exits (normally or on error), _my_cleanup runs automatically
```

## SSH automation

```bash
fl_require_cmd ssh

user=$(fl_ask "Username:")
pass=$(fl_ask_secret "Password:")

HOSTS=(
    server1.example.com
    server2.example.com
)

for host in "${HOSTS[@]}"; do
    fl_ssh_run "$host" "$user" "$pass" "echo hello; uptime"
done
```

Password authentication is handled automatically. The library tries these methods in order:

1. `SSH_ASKPASS_REQUIRE=force` (OpenSSH 8.4+, zero dependencies)
2. `SSH_ASKPASS` + `setsid` (older Linux)
3. `sshpass` (if installed)

## Standalone scripts

If you need to send a single-file script to someone who doesn't have the library, you can copy the contents of `franlib.sh` into the top of your script. The only change needed is removing the source guard (lines 7-8):

```bash
if [[ -n "${_FL_SOURCED:-}" ]]; then return 0; fi
_FL_SOURCED=1
```

The `return` statement is only valid inside sourced scripts, so it will cause an error if executed directly.

## Testing

```sh
bash test_franlib.sh
```

## Linting

```sh
shellcheck -x -s bash franlib.sh example_ssh_batch.sh example_ssh_hello.sh example_basic.sh test_franlib.sh
```
