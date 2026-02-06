#!/bin/bash
# example_basic.sh — Test basic franlib.sh functionalities
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/franlib.sh"

fl_info "This is an example script testing basic functionalities."

fl_info "Running: echo \"Hello this is the first command!\""
fl_run echo "Hello this is the first command!"

fl_info "Running: cd ~/dotfiles"
fl_run cd ~/dotfiles

fl_info "Running: eza -ls"
fl_require_cmd eza "https://github.com/eza-community/eza"
fl_run eza -1

fl_info "Running: dynamic progress counter"
fl_run sh -c 'for i in $(seq 1 20); do printf "\rProgress: %d/20" $i; sleep 0.1; done; echo'

fl_info "Running: curl download"
fl_run curl -o /dev/null https://dl.google.com/go/go1.22.0.linux-amd64.tar.gz
