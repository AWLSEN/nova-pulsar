#!/bin/bash
# resolve-namespace.sh - Detect and handle project folder renames
#
# Usage: source resolve-namespace.sh; resolve_namespace
#   Or: ./resolve-namespace.sh [project-path]
#
# Returns the namespace name, auto-renaming if folder was renamed.
# This script is used by nova.md and pulsar.md to ensure namespace consistency.

set -euo pipefail

COMMS_BASE="$HOME/comms/plans"

# Resolve namespace for a project path
# If folder was renamed, updates the namespace to match
# Prints the resolved namespace name
resolve_namespace() {
    local project_path="${1:-$PWD}"
    local current_name=$(basename "$project_path")
    local resolved_namespace=""

    # First check if namespace with current name exists and matches path
    if [ -f "$COMMS_BASE/$current_name/config.json" ]; then
        local stored_path=$(jq -r '.projectPath // ""' "$COMMS_BASE/$current_name/config.json" 2>/dev/null || echo "")
        if [ "$stored_path" = "$project_path" ]; then
            # Perfect match
            echo "$current_name"
            return 0
        fi
    fi

    # Search all namespaces for matching projectPath
    for config_file in "$COMMS_BASE"/*/config.json; do
        [ -f "$config_file" ] || continue

        local stored_path=$(jq -r '.projectPath // ""' "$config_file" 2>/dev/null || echo "")
        if [ "$stored_path" = "$project_path" ]; then
            local old_namespace=$(basename "$(dirname "$config_file")")

            # Found! Folder was renamed
            if [ "$old_namespace" != "$current_name" ]; then
                # Check if target namespace already exists
                if [ -d "$COMMS_BASE/$current_name" ]; then
                    echo "WARNING: Cannot rename namespace '$old_namespace' to '$current_name' - target exists" >&2
                    echo "$old_namespace"
                    return 0
                fi

                # Rename namespace directory
                echo "Detected folder rename: $old_namespace -> $current_name" >&2
                mv "$COMMS_BASE/$old_namespace" "$COMMS_BASE/$current_name"

                # Update config.json with new name
                local tmp_config=$(mktemp)
                jq --arg name "$current_name" '.projectName = $name' \
                    "$COMMS_BASE/$current_name/config.json" > "$tmp_config"
                mv "$tmp_config" "$COMMS_BASE/$current_name/config.json"

                echo "Namespace renamed: $old_namespace -> $current_name" >&2
            fi

            echo "$current_name"
            return 0
        fi
    done

    # No existing namespace found - return current name (will be created fresh)
    echo "$current_name"
    return 0
}

# If run directly (not sourced), execute with optional path argument
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    resolve_namespace "${1:-$PWD}"
fi
