#!/bin/bash
# migrate-all-projects.sh - Migrate all projects from old structure to new
#
# Migrates all projects in ~/comms/plans/ from the old structure to new:
# - review/ → completed/
# - archived/ → completed/
# - Updates board.json status fields
#
# Usage: ./migrate-all-projects.sh [--dry-run]

set -e

COMMS_BASE="$HOME/comms/plans"
DRY_RUN=false

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
    echo ""
fi

log() {
    echo -e "${BLUE}[migrate]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Migrate a single project
migrate_project() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")
    local changes_made=false

    log "Checking project: $project_name"

    # Check for review/ directory
    if [ -d "$project_dir/review" ]; then
        local review_count=$(ls "$project_dir/review" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$review_count" -gt 0 ]; then
            echo "  Found $review_count plans in review/"
            if [ "$DRY_RUN" = false ]; then
                mkdir -p "$project_dir/completed"
                cp -r "$project_dir/review/"* "$project_dir/completed/" 2>/dev/null || true
                rm -rf "$project_dir/review"
                success "Migrated review/ → completed/"
            else
                echo "  Would migrate review/ → completed/"
            fi
            changes_made=true
        fi
    fi

    # Check for archived/ directory
    if [ -d "$project_dir/archived" ]; then
        local archived_count=$(ls "$project_dir/archived" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$archived_count" -gt 0 ]; then
            echo "  Found $archived_count plans in archived/"
            if [ "$DRY_RUN" = false ]; then
                mkdir -p "$project_dir/completed"
                cp -r "$project_dir/archived/"* "$project_dir/completed/" 2>/dev/null || true
                rm -rf "$project_dir/archived"
                success "Migrated archived/ → completed/"
            else
                echo "  Would migrate archived/ → completed/"
            fi
            changes_made=true
        fi
    fi

    # Update board.json
    if [ -f "$project_dir/board.json" ]; then
        if grep -q '"status": "review"\|"status": "archived"' "$project_dir/board.json" 2>/dev/null; then
            echo "  Found old status entries in board.json"
            if [ "$DRY_RUN" = false ]; then
                if command -v jq >/dev/null 2>&1; then
                    local temp_file=$(mktemp)
                    jq '(.plans[]? | select(.status == "review" or .status == "archived") | .status) = "completed" |
                        (.plans[]? | select(.path) | .path) |= gsub("/(review|archived)/"; "/completed/")' \
                        "$project_dir/board.json" > "$temp_file" 2>/dev/null && mv "$temp_file" "$project_dir/board.json" || rm -f "$temp_file"
                    success "Updated board.json"
                else
                    sed -i.bak 's/"status": "review"/"status": "completed"/g; s/"status": "archived"/"status": "completed"/g; s|/review/|/completed/|g; s|/archived/|/completed/|g' "$project_dir/board.json" 2>/dev/null || true
                    rm -f "$project_dir/board.json.bak"
                    success "Updated board.json (sed fallback)"
                fi
            else
                echo "  Would update board.json status entries"
            fi
            changes_made=true
        fi
    fi

    if [ "$changes_made" = false ]; then
        echo "  No migration needed"
    fi

    echo ""
}

# Main
main() {
    echo -e "${GREEN}Starry Night - Global Migration${NC}"
    echo "=================================="
    echo ""

    if [ ! -d "$COMMS_BASE" ]; then
        log "No comms directory found at $COMMS_BASE"
        exit 0
    fi

    # Find all project directories
    local project_count=0
    local migrated_count=0

    for project_dir in "$COMMS_BASE"/*; do
        if [ -d "$project_dir" ] && [ "$(basename "$project_dir")" != ".*" ]; then
            migrate_project "$project_dir"
            project_count=$((project_count + 1))
        fi
    done

    echo "=================================="
    echo ""
    if [ "$DRY_RUN" = true ]; then
        success "Dry run complete! Checked $project_count projects"
        echo ""
        echo "Run without --dry-run to apply changes:"
        echo "  ./scripts/migrate-all-projects.sh"
    else
        success "Migration complete! Processed $project_count projects"
        echo ""
        echo "Old structure (review/, archived/) has been migrated to completed/"
    fi
}

main
