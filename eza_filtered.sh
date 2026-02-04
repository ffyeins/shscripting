#!/usr/bin/env bash
#
# eza_filtered.sh — Run eza with filtered tree output
#
# Usage: ./eza_filtered.sh
#
# This script runs 'eza -F -a -T -L 4' but modifies the output with these rules:
# - Show depth 3 (not 4)
# - Limit subdirectories to 5 items max (show "└── ..." if 6+ items)
# - Show all items in root directory (no limit)
# - If level 3 subdirectory has children, show "└── ..." under it
# - If level 3 subdirectory is empty, show "└── (empty)" under it
#
# Requires:
# - bash 4.0+ (for associative arrays)
# - eza (modern replacement for ls)

set -euo pipefail

# Check bash version (need 4.0+ for associative arrays)
if ((BASH_VERSINFO[0] < 4)); then
    echo "[WARN] This script requires bash 4.0 or later. Current version: $BASH_VERSION" >&2
    echo "[WARN] On macOS, install via: brew install bash" >&2
    exit 1
fi

# Check if eza is installed
if ! command -v eza &>/dev/null; then
    echo "[WARN] eza is not installed. Please install it first." >&2
    echo "[WARN] Install via: brew install eza" >&2
    exit 1
fi

# Run eza with depth 4 to capture full tree for analysis
lines=()
while IFS= read -r line; do
    lines+=("$line")
done < <(eza -F -a -T -L 4)

# Function to strip ANSI color codes
strip_ansi() {
    local text="$1"
    # Remove ANSI escape sequences (ESC [ ... m)
    echo "$text" | sed 's/\x1b\[[0-9;]*m//g'
}

# Function to calculate depth from tree characters
get_depth() {
    local line="$1"
    local clean
    clean=$(strip_ansi "$line")
    # Count the tree structure characters before the actual name
    # Each level adds 4 characters (│   , ├── , └── )
    local prefix="${clean%%[^│ ├└─]*}"
    local len=${#prefix}
    echo $((len / 4))
}

# Function to check if a line represents a directory
is_directory() {
    local line="$1"
    local clean
    clean=$(strip_ansi "$line")
    [[ "$clean" =~ /[[:space:]]*$ ]]
}

# Function to create indentation string
make_indent() {
    local depth=$1
    local is_last=${2:-0}
    local result=""
    for ((i = 0; i < depth; i++)); do
        if ((i < depth - 1)); then
            result+="│   "
        elif ((is_last)); then
            result+="└── "
        else
            result+="├── "
        fi
    done
    echo "$result"
}

# Process lines
declare -A dir_counts  # Count items in each directory
declare -A dir_shown   # Track how many items shown per directory
declare -A dir_has_children  # Track if depth-3 dirs have children
declare -A dir_is_empty  # Track if depth-3 dirs are empty
declare -a dir_stack   # Stack to track current directory path
declare -a output_lines  # Final output

# First pass: analyze the tree structure
prev_depth=0
dir_path=""
for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue

    depth=$(get_depth "$line")

    # Update directory path stack
    while ((${#dir_stack[@]} > depth)); do
        unset 'dir_stack[-1]'
    done

    if ((depth > 0)); then
        parent_path="${dir_stack[*]}"
        [[ -n "$parent_path" ]] && parent_path="${parent_path// /:}"

        # Count items in parent directory
        ((dir_counts["$parent_path"]++))

        # Mark depth-3 directories that are empty (assume empty until proven otherwise)
        if is_directory "$line" && ((depth == 3)); then
            dir_stack[depth]="$line"
            current_path="${dir_stack[*]}"
            current_path="${current_path// /:}"
            dir_is_empty["$current_path"]=1
        fi

        # If we see depth 4, mark the depth-3 parent as having children
        if ((depth == 4)); then
            parent_depth3="${dir_stack[*]:0:4}"
            parent_depth3="${parent_depth3// /:}"
            unset dir_is_empty["$parent_depth3"]
            dir_has_children["$parent_depth3"]=1
        fi
    fi

    if is_directory "$line"; then
        dir_stack[depth]="$line"
    fi

    prev_depth=$depth
done

# Second pass: build filtered output
prev_depth=0
dir_stack=()
for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue

    depth=$(get_depth "$line")

    # Update directory path stack
    while ((${#dir_stack[@]} > depth)); do
        unset 'dir_stack[-1]'
    done

    # Root level: show everything
    if ((depth == 0)); then
        output_lines+=("$line")
        if is_directory "$line"; then
            dir_stack[0]="$line"
        fi
        continue
    fi

    # Depth 4: skip (we only show up to depth 3)
    if ((depth >= 4)); then
        continue
    fi

    # For depth 1-3: apply item limit (5 items max per subdirectory)
    parent_path="${dir_stack[*]:0:depth}"
    parent_path="${parent_path// /:}"

    item_num=$((++dir_shown["$parent_path"]))
    max_items=5

    if ((item_num <= max_items)); then
        output_lines+=("$line")

        if is_directory "$line"; then
            dir_stack[depth]="$line"
            current_path="${dir_stack[*]}"
            current_path="${current_path// /:}"

            # If this is a depth-3 directory, add markers
            if ((depth == 3)); then
                if [[ -n "${dir_is_empty[$current_path]:-}" ]]; then
                    # Empty directory
                    indent="$(make_indent $((depth + 1)) 1)"
                    output_lines+=("${indent}(empty)")
                elif [[ -n "${dir_has_children[$current_path]:-}" ]]; then
                    # Has children
                    indent="$(make_indent $((depth + 1)) 1)"
                    output_lines+=("${indent}...")
                fi
            fi
        fi
    elif ((item_num == max_items + 1)); then
        # Show ellipsis after hitting the limit
        indent="$(make_indent "$depth" 1)"
        output_lines+=("${indent}...")
    fi
done

# Print final output
printf '%s\n' "${output_lines[@]}"
