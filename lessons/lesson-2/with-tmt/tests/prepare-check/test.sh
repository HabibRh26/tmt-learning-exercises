#!/bin/bash
echo "Checking if prepare step created the workspace..."
if ! test -f /tmp/test-workspace/ready.txt; then
    echo "FAIL: /tmp/test-workspace/ready.txt not found"
    exit 1
fi
echo "PASS: workspace ready"

echo "Checking if tree is available (installed by prepare)..."
if ! tree --version > /dev/null 2>&1; then
    echo "FAIL: tree is not installed"
    exit 1
fi
echo "PASS: tree installed"

echo "All checks passed."
