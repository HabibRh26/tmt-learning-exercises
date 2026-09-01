#!/bin/bash
curl --version
if [ $? -eq 0 ]; then
    echo "PASS: curl works"
    exit 0
else
    echo "FAIL: curl not found"
    exit 1
fi
