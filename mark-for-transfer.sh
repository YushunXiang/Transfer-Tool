#!/bin/bash

# Script to mark directories as ready for transfer
# Usage: mark-for-transfer.sh /path/to/directory

if [ $# -eq 0 ]; then
    echo "Usage: $0 <directory_path>"
    echo "Marks a directory as ready for transfer to robot-reasoning cluster"
    exit 1
fi

DIRECTORY="$1"

if [ ! -d "$DIRECTORY" ]; then
    echo "Error: $DIRECTORY is not a valid directory"
    exit 1
fi

# Create marker file
touch "$DIRECTORY/.ready_for_transfer"

if [ $? -eq 0 ]; then
    echo "Successfully marked $DIRECTORY for transfer"
    echo "The embodied-upload service will process this directory shortly"
else
    echo "Error: Failed to mark $DIRECTORY for transfer"
    exit 1
fi