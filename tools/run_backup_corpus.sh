#!/bin/bash
# Compile every TilemillProject with the swift carto; report failures.
PASS=0; FAIL=0
for mml in /Users/trasch/Projects/Backup/TilemillProjects/*/project.mml; do
    project=$(basename "$(dirname "$mml")")
    if OUT=$(/Users/trasch/Projects/swift-carto/.build/debug/carto "$mml" 2>/tmp/opencode/carto-err.txt) && [ -n "$OUT" ]; then
        PASS=$((PASS+1))
    else
        echo "FAIL $project: $(head -2 /tmp/opencode/carto-err.txt)"
        FAIL=$((FAIL+1))
    fi
done
echo "== PASS: $PASS FAIL: $FAIL"
