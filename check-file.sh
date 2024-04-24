#!/usr/bin/bash

# Check if a specific file exists and is executable
FILE="~/bsc-kvm-config.json"
if [ -f "$FILE" ]; then
    if [ -x "$FILE" ]; then
        echo "$FILE exists and is executable."
    else
        echo "$FILE is not executable. Setting execute permission."
        chmod +x "$FILE"
    fi
else
    echo "$FILE does not exist."
fi