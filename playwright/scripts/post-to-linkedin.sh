#!/bin/bash

# Check if required arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <username> <password> <content>"
    exit 1
fi

# Set environment variables
export LINKEDIN_USERNAME="$1"
export LINKEDIN_PASSWORD="$2"
export POST_CONTENT="$3"

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLAYWRIGHT_DIR="$(dirname "$SCRIPT_DIR")"

# Change to the playwright directory and run the test
cd "$PLAYWRIGHT_DIR" && npx playwright test tests/linkedin-post.spec.ts