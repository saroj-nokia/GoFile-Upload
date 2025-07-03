#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Script Information ---
# This script uploads a specified file to GoFile.io and displays the download link.
# It performs various checks to ensure robustness.

# --- Error Handling Function ---
# A function to print error messages to stderr and exit.
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# --- Argument Check ---
# Check if a file argument is provided.
if [[ "$#" -eq 0 ]]; then
    error_exit "No file specified! Usage: $0 <file_path>"
fi

# Store the file path.
FILE="$1"

# --- File Existence and Readability Check ---
# Verify that the specified file exists and is readable.
if [[ ! -f "$FILE" ]]; then
    error_exit "File '$FILE' does not exist."
elif [[ ! -r "$FILE" ]]; then
    error_exit "File '$FILE' exists but is not readable."
fi

# --- Dependency Check ---
# Check for required commands (curl and jq).
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        error_exit "Required command '$cmd' is not installed! Please install it."
    fi
done

# --- GoFile API Interaction ---

# Query GoFile API to find the best server.
echo "Fetching best GoFile server..."
SERVER=$(curl -s --fail https://api.gofile.io/servers | jq -r '.data.servers[0].name' 2>/dev/null)

# Validate server name.
if [[ -z "$SERVER" || "$SERVER" == "null" ]]; then
    error_exit "Failed to retrieve server name from GoFile API! The API response might be unexpected."
fi
echo "Using GoFile server: ${SERVER}"

# Upload the file to GoFile.
echo "Uploading file '$FILE' to GoFile..."
# Use -# for progress meter, --fail for non-200 exit, -F for form data.
LINK=$(curl -# --fail -F "file=@$FILE" "https://${SERVER}.gofile.io/uploadFile" | jq -r '.data.downloadPage' 2>/dev/null)

# Validate download link.
if [[ -z "$LINK" || "$LINK" == "null" ]]; then
    error_exit "Failed to upload file or retrieve download link! Check GoFile API response or file size."
fi

# --- Success Output ---
echo "" # Add a newline for better readability
echo "File uploaded successfully!"
echo "Download Link: $LINK"
echo "" # Another newline
