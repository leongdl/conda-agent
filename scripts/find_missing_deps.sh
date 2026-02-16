#!/usr/bin/env bash
# find_missing_deps.sh — Reusable script to find missing shared library dependencies
# for a given application directory.
#
# Usage: ./find_missing_deps.sh <app_root_dir> [additional_lib_dirs...]
# Example: ./find_missing_deps.sh /tmp/maya-extract/usr/autodesk/maya2026
#
# Output files written to ../analysis/ relative to this script:
#   missing_deps.txt   — libs not found anywhere
#   system_deps.txt    — libs resolved from system (candidates to bundle)
#   all_needed.txt     — all unique NEEDED libs
#   all_provided.txt   — all libs provided by the app

set -uo pipefail

APP_ROOT="${1:?Usage: $0 <app_root_dir> [extra_lib_dirs...]}"
shift
EXTRA_LIB_DIRS=("$@")

WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

echo "=== Scanning ELF binaries under: $APP_ROOT ==="

# 1. Find all ELF files
find "$APP_ROOT" -type f \( -name "*.so" -o -name "*.so.*" -o -executable \) > "$WORK_DIR/candidates.txt" 2>/dev/null

echo "Found $(wc -l < "$WORK_DIR/candidates.txt") candidate files"

# Filter to actual ELF and extract NEEDED
> "$WORK_DIR/all_needed_raw.txt"
while IFS= read -r f; do
    if readelf -h "$f" &>/dev/null; then
        readelf -d "$f" 2>/dev/null | grep NEEDED | sed 's/.*\[//;s/\]//' >> "$WORK_DIR/all_needed_raw.txt"
    fi
done < "$WORK_DIR/candidates.txt"

sort -u "$WORK_DIR/all_needed_raw.txt" > "$WORK_DIR/all_needed.txt"

# 2. Collect all .so files provided by the app (files + symlinks)
find "$APP_ROOT" \( -type f -o -type l \) \( -name "*.so" -o -name "*.so.*" \) -exec basename {} \; 2>/dev/null | \
    sort -u > "$WORK_DIR/all_provided.txt"

NEEDED_COUNT=$(wc -l < "$WORK_DIR/all_needed.txt")
PROVIDED_COUNT=$(wc -l < "$WORK_DIR/all_provided.txt")
echo "Total unique NEEDED libs: $NEEDED_COUNT"
echo "Total libs provided by app: $PROVIDED_COUNT"

# 3. Find libs not provided by the app
comm -23 "$WORK_DIR/all_needed.txt" "$WORK_DIR/all_provided.txt" > "$WORK_DIR/not_in_app.txt"
echo "Libs not in app: $(wc -l < "$WORK_DIR/not_in_app.txt")"

# 4. Resolve against system
> "$WORK_DIR/system_resolved.txt"
> "$WORK_DIR/missing.txt"

while read -r lib; do
    FOUND=$(ldconfig -p 2>/dev/null | grep -oP "=> \K.*/${lib}$" | head -1 || true)
    if [[ -z "$FOUND" ]]; then
        for d in /usr/lib64 /usr/lib /lib64 /lib /usr/lib/x86_64-linux-gnu; do
            if [[ -f "$d/$lib" || -L "$d/$lib" ]]; then
                FOUND="$d/$lib"
                break
            fi
        done
    fi
    if [[ -n "$FOUND" ]]; then
        echo "$lib => $FOUND" >> "$WORK_DIR/system_resolved.txt"
    else
        echo "$lib" >> "$WORK_DIR/missing.txt"
    fi
done < "$WORK_DIR/not_in_app.txt"

echo ""
echo "=== RESULTS ==="
echo "Resolved from system (bundle candidates): $(wc -l < "$WORK_DIR/system_resolved.txt")"
echo "Truly missing (not found anywhere): $(wc -l < "$WORK_DIR/missing.txt")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../analysis"
mkdir -p "$OUTPUT_DIR"

cp "$WORK_DIR/system_resolved.txt" "$OUTPUT_DIR/system_deps.txt"
cp "$WORK_DIR/missing.txt" "$OUTPUT_DIR/missing_deps.txt"
cp "$WORK_DIR/all_needed.txt" "$OUTPUT_DIR/all_needed.txt"
cp "$WORK_DIR/all_provided.txt" "$OUTPUT_DIR/all_provided.txt"

echo ""
echo "Output written to $OUTPUT_DIR/"

if [[ -s "$WORK_DIR/missing.txt" ]]; then
    echo ""
    echo "=== MISSING LIBS (not found anywhere) ==="
    cat "$WORK_DIR/missing.txt"
fi

if [[ -s "$WORK_DIR/system_resolved.txt" ]]; then
    echo ""
    echo "=== SYSTEM LIBS (should bundle into package) ==="
    cat "$WORK_DIR/system_resolved.txt"
fi
