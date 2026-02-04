# shscripting — bash helper library

## Project overview

`franlib.sh` is a bash helper library that other shell scripts source for common functionality: colored output, command logging, user input, command execution, SSH automation, and cleanup handling. The goal is minimal dependencies so scripts can be shared with anyone who has bash.

## Files

- `franlib.sh` — the library (source it, don't execute it)
- `example_ssh_batch.sh` — example script demonstrating SSH batch execution
- `example_ssh_hello.sh` — example script demonstrating SSH greeting commands
- `example_basic.sh` — example script testing basic franlib.sh functionalities
- `test_franlib.sh` — test suite (26 tests)
- `ignore/` — reference scripts kept for convenience; ignore this directory and its contents unless explicitly told to reference them

## Shell compatibility

Target `#!/bin/bash`. Requires bash 4.0+.

## Coding conventions

- Use 4 spaces for indentation (not tabs)
- Use `[[ ]]` for conditionals; use `case` for pattern matching
- Use `local` for function-scoped variables
- Use `command -v` for command existence checks (not `which`)
- Use `read -s` for secret input
- Use bash arrays for lists
- All library functions prefixed with `fl_`; internal functions prefixed with `_fl_`
- All messages go to stderr so stdout stays clean for data
- Colors only when `[[ -t 2 ]]` (stderr is a terminal)

## Testing

```sh
bash test_franlib.sh
```

## Linting

```sh
# Library (standalone)
shellcheck -s bash franlib.sh

# All files (follow source directives)
shellcheck -x -s bash franlib.sh example_ssh_batch.sh example_ssh_hello.sh example_basic.sh test_franlib.sh
```

Expected: zero warnings. SC2329 (info) on test file is a false positive for indirectly-invoked cleanup functions.

## Output functions

The library provides colored output functions for different message types:

- `fl_info` — informational messages (cyan tag `[INFO]`, default message text)
- `fl_warn` — warning messages (entire line in yellow: `[WARN] message`)
- `fl_error` — error messages (entire line in bold red: `[ERROR] message`)
- `fl_success` — success messages (entire line in green: `[SUCCESS] message`)
- `fl_print_command` — command logging (cyan tag `[COMMAND]`, default message text)

For `fl_warn`, `fl_error`, and `fl_success`, the entire line (tag and message) is colored. All output goes to stderr to keep stdout clean for data.

## User input

`fl_ask` prompts for user input and returns the value. `fl_ask_secret` prompts for secret input (passwords) without echoing to the terminal. `fl_confirm` pauses execution and waits for the user to press ENTER to continue. It accepts an optional custom prompt (defaults to "Press ENTER to continue...") and always returns 0.

## Command execution

`fl_run` is the central place for command execution. It logs every command to stderr via `fl_print_command` before running it, so script output always shows what was executed. Both `fl_run_or_die` and `fl_run_capture` delegate to `fl_run`, so all command variants produce consistent logging. Prefer `fl_run` (and its variants `fl_run_or_die`, `fl_run_capture`) over calling commands directly.

## SSH automation

SSH password automation uses `SSH_ASKPASS` with `SSH_ASKPASS_REQUIRE=force` (OpenSSH 8.4+, Sep 2020) as the primary method — zero external dependencies. Falls back to `SSH_ASKPASS` + `setsid` on older Linux, then to `sshpass` if installed.

SSH options are stored in the `_FL_SSH_OPTS` array and shared across all SSH methods. Askpass script creation is handled by `_fl_ssh_make_askpass`, which uses single-quoted passwords with proper escaping to handle special characters (`'`, `"`, `$`, `` ` ``, `\`).

`fl_ssh_run` logs the logical SSH command (with the password omitted) via `fl_print_command` before dispatching to the appropriate method.

## Iteration pattern

Use arrays for host lists:

```bash
HOSTS=(
    server1.example.com
    server2.example.com
)

for host in "${HOSTS[@]}"; do
    fl_ssh_run "$host" "$user" "$pass" "$cmds"
done
```
