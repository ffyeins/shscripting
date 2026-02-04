# Creating an .sh helper script

I want to create an .sh helper script that other sh scripts can source and use the functions from the helper script.

The reason for this is that I need to be able to write scripts that can be shared with people that might not have python, go, or tmux installed. I want to minimize the dependencies as much as possible.

Let us plan on how we will approach development.

Search the best practices on how to approach the creation of this sh script.

Target #!/bin/sh only — no bashisms, no external dependencies beyond standard POSIX utilities. This ensures it works on dash (Debian/Ubuntu), ash (Alpine/BusyBox), bash-in-sh-mode (macOS), and FreeBSD sh.

Works on macOS and Linux — must work on dash (Debian/Ubuntu), ash (Alpine/BusyBox), bash-in-sh-mode (macOS), and FreeBSD sh

Terminal passthrough — commands run as if the user typed them directly:
- Support dynamic progress output (scp, wget, curl)
- Inherit stdin for interactive commands

Simple development — creating a new script = creating one .sh file that sources the library

The helper script should be named `franlib.sh`. The prefix for function names should be `fl_`.

I can think on starting with this:

```
# franlib.sh — POSIX sh scripting helper library
#
# Source this file from your scripts:
#   SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
#   . "$SCRIPT_DIR/franlib.sh"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

_FL_CYAN=''
_FL_RED='\033[1;31m'
_FL_RESET='\033[0m'

# ---------------------------------------------------------------------------
# User input
# ---------------------------------------------------------------------------

# fl_ask
# Read a line from stdin and print it to stdout (trimmed).
# Usage: name=$(fl_ask)
fl_ask() {
    local input
    read -r input
    printf '%s' "$input"
}

# fl_ask_secret
# Read a line from stdin without echoing (for passwords).
# Restores echo on interrupt via the EXIT trap.
# Usage: pass=$(fl_ask_secret)
fl_ask_secret() {
    stty -echo
    local input
    read -r input
    stty echo
    printf '\n' >&2
    printf '%s' "$input"
}
```

I would also like to include methods for printing messages. Use cyan for normal messages, and red bold text for error messages.

I would also want the script to be able to read the commands ran outputs, and work with that information.

Many of the scripts I want to run will involve connecting to remote environments (for example, via ssh). I want the script to be able to do things like automatically input a password. Is it possible to do this without downloading `expect`?

I common example script that I would like to create would be one that does the following:

```
Ask the user for username.
Let user input the username.
Ask the user for password.
Let the user input the password (do not show it).
For each hostname declared in an array inside the example script:
- Run 'ssh username@hostname' and wait for the prompt that asks for the password
- Input the password
- Wait the command to finish
- If the ssh command had an error, stop the script and show the error.
- If the ssh command was successful, wait for the remote terminal prompt text ($ or %).
- Run some commands in the remote terminal.
```

