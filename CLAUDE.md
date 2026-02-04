# shscripting — POSIX sh helper library

## Project overview

`franlib.sh` is a POSIX sh helper library that other shell scripts source for common functionality: colored output, user input, command execution, SSH automation, and cleanup handling. The goal is minimal dependencies so scripts can be shared with anyone who has a standard POSIX shell.

## Files

- `franlib.sh` — the library (source it, don't execute it)
- `example_ssh_batch.sh` — example script demonstrating SSH batch execution
- `test_franlib.sh` — test suite (16 tests)

## Shell compatibility

Target `#!/bin/sh` only. Must work on:
- dash (Debian/Ubuntu)
- ash (Alpine/BusyBox)
- bash in sh mode (macOS)
- FreeBSD sh

## Coding conventions

- No bashisms: no `[[ ]]`, no arrays, no `${var//pat/rep}`, no `read -s`
- Use `[ ]` and `case` for conditionals
- Use `local` — not POSIX but works on all target shells (suppress SC3043)
- Use `command -v` for command existence checks (not `which`)
- Use `stty -echo` for secret input
- Newline-delimited strings + `set --` instead of arrays
- All library functions prefixed with `fl_`; internal functions prefixed with `_fl_`
- All messages go to stderr so stdout stays clean for data
- Colors only when `[ -t 2 ]` (stderr is a terminal)

## Testing

```sh
# Run tests with macOS default shell
sh test_franlib.sh

# Run tests with bash POSIX mode
bash --posix test_franlib.sh
```

## Linting

```sh
# Library (standalone)
shellcheck -s sh franlib.sh

# All files (follow source directives)
shellcheck -x -s sh franlib.sh example_ssh_batch.sh test_franlib.sh
```

Expected: zero warnings. SC3043 (`local`) is suppressed via directive. SC2329 (info) on test file is a false positive for indirectly-invoked cleanup functions.

## SSH automation

SSH password automation uses `sshpass` as a soft dependency (`SSHPASS="$pw" sshpass -e ssh ...`). On Linux without sshpass, falls back to `SSH_ASKPASS` + `setsid`. The library prints install instructions if neither method is available.

SSH options for automation: `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR`.

## Iteration pattern

Use `while read` with heredoc for host lists — no subshell, so `fl_die` and variable mutation work:

```sh
while IFS= read -r host; do
    [ -z "$host" ] && continue
    fl_ssh_run "$host" "$user" "$pass" "$cmds"
done <<EOF
server1.example.com
server2.example.com
EOF
```
