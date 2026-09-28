#!/bin/sh
set -eu

passes_dir=${1:?usage: prune-visual-passes.sh PASSES_DIR [KEEP_COUNT]}
keep_count=${2:-3}

case "$keep_count" in
    ''|*[!0-9]*)
        echo "ERROR: KEEP_COUNT must be a non-negative integer." >&2
        exit 2
        ;;
esac

test -d "$passes_dir" || exit 0

find "$passes_dir" -mindepth 1 -maxdepth 1 -type d -name 'pass-*' -print \
    | sort -V \
    | awk -v keep="$keep_count" '{ paths[NR]=$0 } END { for (i=1; i<=NR-keep; i++) print paths[i] }' \
    | while IFS= read -r obsolete; do
        case "$obsolete" in
            "$passes_dir"/pass-*)
                echo "Removing superseded visual archive: $obsolete"
                rm -rf -- "$obsolete"
                ;;
            *)
                echo "ERROR: Refusing unexpected visual archive path: $obsolete" >&2
                exit 3
                ;;
        esac
    done
