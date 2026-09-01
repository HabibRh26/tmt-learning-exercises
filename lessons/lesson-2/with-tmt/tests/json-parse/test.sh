#!/bin/bash
echo '{"name": "tmt", "version": 2}' | jq '.name'
if [ $? -eq 0 ]; then
    echo "PASS: jq parsed JSON successfully"
    exit 0
else
    echo "FAIL: jq could not parse JSON"
    exit 1
fi
