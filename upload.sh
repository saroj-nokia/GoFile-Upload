#!/bin/bash

# Check if a file argument is provided
if [[ "$#" -eq 0 ]]; then
    echo "ERROR: No file specified!" >&2
    exit 1
fi

# Store the file path
FILE="$1"

# Check if the file exists and is readable
if [[ ! -f "$FILE" || ! -r "$FILE" ]]; then
    echo "ERROR: File '$FILE' does not exist or is not readable!" >&2
    exit 1
fi

# Check for required commands
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Required command '$cmd' is not installed!" >&2
        exit 1
    fi
done

# Query GoFile API to find the best server
SERVER=$(curl -s --fail https://api.gofile.io/servers | jq -r '.data.servers[0].name' 2>/dev/null)
if [[ -z "$SERVER" || "$SERVER" == "null" ]]; then
    echo "ERROR: Failed to retrieve server name from GoFile API!" >&2
    exit 1
fi

# Upload the file to GoFile
LINK=$(curl -# --fail -F "file=@$FILE" "https://${SERVER}.gofile.io/uploadFile" | jq -r '.data.downloadPage' 2>/dev/null)
if [[ -z "$LINK" || "$LINK" == "null" ]]; then
    echo "ERROR: Failed to upload file or retrieve download link!" >&2
    exit 1
fi

# Display the download link
echo "$LINK"
echo
