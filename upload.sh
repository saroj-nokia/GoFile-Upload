#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Script Information ---
# This script uploads a specified file to GoFile.io and displays the download link.
# Optimized for large files (e.g., compressed files, images, ROMs 1-4 GB).

# --- Error Handling Function ---
# A function to print error messages to stderr and exit.
error_exit() {
    echo "ERROR: $1" >&2
    # Clean up temp files on error
    [[ -n "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
    exit 1
}

# --- Cleanup trap ---
# Ensure temp files are cleaned up on exit
trap '[[ -n "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"' EXIT

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

# --- Display File Info ---
FILE_SIZE_BYTES=$(stat -f%z "$FILE" 2>/dev/null || stat -c%s "$FILE" 2>/dev/null)
FILE_SIZE_HUMAN=$(du -h "$FILE" | cut -f1)
FILE_NAME=$(basename "$FILE")

echo "File: $FILE_NAME"
echo "Size: $FILE_SIZE_HUMAN"
echo ""

# Detect if this is a large file (>500MB) that might take time
LARGE_FILE=false
if [[ $FILE_SIZE_BYTES -gt 524288000 ]]; then
    LARGE_FILE=true
fi

# --- GoFile API Interaction ---

# Query GoFile API to find the best server.
echo "Fetching best GoFile server..."

# Create temp file for server response
TEMP_FILE=$(mktemp) || error_exit "Failed to create temporary file!"

# Fetch server list to temp file
if ! curl -s --fail --connect-timeout 10 --max-time 30 \
    https://api.gofile.io/servers -o "$TEMP_FILE" 2>&1; then
    rm -f "$TEMP_FILE"
    error_exit "Failed to connect to GoFile API! Please check your internet connection."
fi

# Parse the server response
SERVER=$(jq -r '.data.servers[0].name' "$TEMP_FILE" 2>&1)
JQ_EXIT=$?

# Check if jq parsing succeeded
if [[ $JQ_EXIT -ne 0 ]]; then
    echo "API Response:" >&2
    cat "$TEMP_FILE" >&2
    rm -f "$TEMP_FILE"
    error_exit "Failed to parse GoFile API response! The API might have returned unexpected data."
fi

# Validate server name.
if [[ -z "$SERVER" || "$SERVER" == "null" ]]; then
    echo "API Response:" >&2
    cat "$TEMP_FILE" >&2
    rm -f "$TEMP_FILE"
    error_exit "Failed to retrieve valid server name from GoFile API! No servers available."
fi

echo "Using GoFile server: ${SERVER}"
echo ""

# Upload the file to GoFile.
echo "Uploading file '$FILE_NAME' to GoFile..."

# Show appropriate message based on file size
if [[ $LARGE_FILE == true ]]; then
    if [[ $FILE_SIZE_BYTES -gt 1073741824 ]]; then  # >1GB
        echo "This is a large file - upload may take 5-15+ minutes..."
    else
        echo "This may take a few minutes..."
    fi
else
    echo "Uploading..."
fi
echo ""

# Use temp file for upload response to avoid storing large responses in memory
# Increased timeout to 600s (10 min) for large files
if ! curl -# --fail --connect-timeout 10 --max-time 600 \
    -F "file=@$FILE" "https://${SERVER}.gofile.io/uploadFile" \
    -o "$TEMP_FILE" 2>&1; then
    rm -f "$TEMP_FILE"
    error_exit "File upload failed! The file might be too large or the server is unavailable."
fi

# Parse the upload response
LINK=$(jq -r '.data.downloadPage' "$TEMP_FILE" 2>&1)
JQ_EXIT=$?

# Check if jq parsing succeeded
if [[ $JQ_EXIT -ne 0 ]]; then
    echo "Upload Response:" >&2
    cat "$TEMP_FILE" >&2
    rm -f "$TEMP_FILE"
    error_exit "Failed to parse upload response! The API might have returned unexpected data."
fi

# Validate download link.
if [[ -z "$LINK" || "$LINK" == "null" ]]; then
    echo "Upload Response:" >&2
    cat "$TEMP_FILE" >&2
    rm -f "$TEMP_FILE"
    error_exit "Failed to retrieve download link! Check the API response above for details."
fi

# Clean up temp file
rm -f "$TEMP_FILE"

# --- Success Output ---
echo ""
echo "✓ File uploaded successfully!"
echo "Download Link: $LINK"
echo ""