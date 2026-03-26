#!/bin/bash
# Clone all Demarch subrepos to match slse layout
set -e
cd /Users/sma/projects/Demarch

clone_line() {
    local line="$1"
    local dir=$(echo "$line" | cut -d'|' -f1)
    local url=$(echo "$line" | cut -d'|' -f2)
    local branch=$(echo "$line" | cut -d'|' -f3)

    if [ -d "$dir/.git" ]; then
        echo "SKIP $dir"
        return 0
    fi

    mkdir -p "$(dirname "$dir")"

    if [ -n "$branch" ]; then
        git clone -b "$branch" --single-branch "$url" "$dir" >/dev/null 2>&1 && echo "OK   $dir" || echo "FAIL $dir ($url)"
    else
        git clone "$url" "$dir" >/dev/null 2>&1 && echo "OK   $dir" || echo "FAIL $dir ($url)"
    fi
}

export -f clone_line

cat /Users/sma/projects/Demarch/subrepos.txt | xargs -P 8 -I{} bash -c 'clone_line "$@"' _ {}

echo ""
echo "=== All done ==="
