#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail

# --- Script Information ---
# This script uploads a specified file to GoFile.io and displays the download link.
# Optimized for large files (e.g., compressed files, images, ROMs 1-4 GB).

VERSION="1.2.0"

# --- Error Handling Function ---
# A function to print error messages to stderr and exit.
error_exit() {
    echo "ERROR: $1" >&2
    # Clean up temp files on error
    [[ -n "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
    [[ -n "$STDERR_FILE" ]] && rm -f "$STDERR_FILE"
    exit 1
}

# --- Cleanup trap ---
# Ensure temp files are cleaned up on exit (success, error, or interrupt)
cleanup() {
    # Capture the exit status we were called with — otherwise the trap's
    # own [[ ]] tests overwrite $?, and callers see the wrong exit code
    # (e.g. -h/--help would report failure even though it printed fine).
    local exit_code=$?
    [[ -n "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
    [[ -n "$STDERR_FILE" ]] && rm -f "$STDERR_FILE"
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# --- Argument Parsing ---
# Token can come from -t/--token, or the GOFILE_TOKEN env var (preferred for
# scripting, since it keeps the token out of shell history / process list).
TOKEN="${GOFILE_TOKEN:-}"
FILE=""

print_usage() {
    echo "GoFile Upload Script v${VERSION}"
    echo "Usage: $0 [-t TOKEN] <file_path>"
    echo ""
    echo "  -t, --token TOKEN   GoFile account API token (ties the upload to your"
    echo "                      account instead of uploading as a guest)."
    echo "                      Can also be set via the GOFILE_TOKEN env var,"
    echo "                      which avoids the token showing up in shell"
    echo "                      history or 'ps' output."
    echo "  -h, --help          Show this help message."
    echo ""
    echo "Find your token at: GoFile.io -> Account -> API Token"
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -t|--token)
            [[ -n "${2:-}" ]] || error_exit "Missing value for $1"
            TOKEN="$2"
            shift 2
            ;;
        --token=*)
            TOKEN="${1#*=}"
            shift
            ;;
        -*)
            error_exit "Unknown option: $1 (use -h for help)"
            ;;
        *)
            if [[ -n "$FILE" ]]; then
                error_exit "Only one file may be uploaded at a time (use -h for help)"
            fi
            FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$FILE" ]]; then
    print_usage
    exit 0
fi

# --- File Existence and Readability Check ---
if [[ ! -f "$FILE" ]]; then
    error_exit "File '$FILE' does not exist."
elif [[ ! -r "$FILE" ]]; then
    error_exit "File '$FILE' exists but is not readable."
fi

# --- Dependency Check ---
for cmd in curl jq stat; do
    if ! command -v "$cmd" &>/dev/null; then
        error_exit "Required command '$cmd' is not installed! Please install it."
    fi
done

# --- Display File Info ---
FILE_SIZE_BYTES=$(stat -f%z "$FILE" 2>/dev/null || stat -c%s "$FILE" 2>/dev/null)
if [[ -z "$FILE_SIZE_BYTES" ]]; then
    error_exit "Could not determine file size for '$FILE'."
fi
FILE_SIZE_HUMAN=$(du -h "$FILE" | cut -f1)
FILE_NAME=$(basename "$FILE")

echo "File: $FILE_NAME"
echo "Size: $FILE_SIZE_HUMAN"
if [[ -n "$TOKEN" ]]; then
    echo "Account: authenticated (token supplied)"
else
    echo "Account: guest (no token — file will be shorter-lived; pass -t/--token to upload to your account)"
fi
echo ""

# Detect if this is a large file (>500MB) that might take time
LARGE_FILE=false
if [[ $FILE_SIZE_BYTES -gt 524288000 ]]; then
    LARGE_FILE=true
fi

# --- GoFile API Interaction ---

echo "Fetching best GoFile server..."

# Separate temp files for response body and stderr, so error output never
# leaks into the JSON we hand to jq.
TEMP_FILE=$(mktemp) || error_exit "Failed to create temporary file!"
STDERR_FILE=$(mktemp) || error_exit "Failed to create temporary file!"

if ! curl -s --fail --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 2 \
    https://api.gofile.io/servers -o "$TEMP_FILE" 2>"$STDERR_FILE"; then
    echo "curl error output:" >&2
    cat "$STDERR_FILE" >&2
    error_exit "Failed to connect to GoFile API! Please check your internet connection."
fi

# GoFile's API can return {"status":"error","message":"..."} — surface that
# message directly instead of just saying a field was missing/null.
check_api_error() {
    local resp_file="$1" context="$2" status msg
    status=$(jq -r '.status // empty' "$resp_file" 2>/dev/null)
    if [[ "$status" == "error" ]]; then
        msg=$(jq -r '.message // "no message provided by the API"' "$resp_file" 2>/dev/null)
        error_exit "GoFile API error while $context: $msg"
    fi
}

check_api_error "$TEMP_FILE" "fetching server list"

# Parse the server response (stdout only — stderr is captured separately above)
if ! SERVER=$(jq -r '.data.servers[0].name' "$TEMP_FILE" 2>"$STDERR_FILE"); then
    echo "API Response:" >&2
    cat "$TEMP_FILE" >&2
    echo "jq error:" >&2
    cat "$STDERR_FILE" >&2
    error_exit "Failed to parse GoFile API response! The API might have returned unexpected data."
fi

if [[ -z "$SERVER" || "$SERVER" == "null" ]]; then
    echo "API Response:" >&2
    cat "$TEMP_FILE" >&2
    error_exit "Failed to retrieve valid server name from GoFile API! No servers available."
fi

echo "Using GoFile server: ${SERVER}"
echo ""

# --- Upload ---
echo "Uploading file '$FILE_NAME' to GoFile..."

if [[ $LARGE_FILE == true ]]; then
    if [[ $FILE_SIZE_BYTES -gt 3221225472 ]]; then  # >3GB
        echo "This is a very large file - upload may take 15-60+ minutes..."
    elif [[ $FILE_SIZE_BYTES -gt 1073741824 ]]; then  # >1GB
        echo "This is a large file - upload may take 10-30 minutes..."
    else
        echo "This may take 5-10 minutes..."
    fi
else
    echo "Uploading..."
fi
echo ""

# Timeout scales with file size:
# - Files < 1GB: 600s (10 min)
# - Files 1-3GB: 1800s (30 min)
# - Files > 3GB: 3600s (60 min)
UPLOAD_TIMEOUT=600
if [[ $FILE_SIZE_BYTES -gt 3221225472 ]]; then  # >3GB
    UPLOAD_TIMEOUT=3600
elif [[ $FILE_SIZE_BYTES -gt 1073741824 ]]; then  # >1GB
    UPLOAD_TIMEOUT=1800
fi

# --retry only helps with connection-establishment failures, not a drop
# mid-upload, but it's a cheap safety net for flaky networks.
# NOTE: stderr is left going to the terminal here (not captured to a file)
# so the -# progress bar stays visible. This curl call's output isn't
# captured into a variable, so there's no risk of it corrupting JSON
# parsing the way the server-list fetch was — that's what the earlier
# STDERR_FILE fix was actually for.
#
# GoFile's own docs are inconsistent about whether the token is expected as
# a form field or an Authorization header — different doc sources show
# different things. Sending both is harmless if only one is actually read,
# and avoids guessing wrong. curl -F/-H args never get echoed anywhere by
# this script, so the token doesn't leak into the visible output.
UPLOAD_ARGS=(-F "file=@${FILE}")
if [[ -n "$TOKEN" ]]; then
    UPLOAD_ARGS+=(-F "token=${TOKEN}" -H "Authorization: Bearer ${TOKEN}")
fi

if ! curl -# --fail --connect-timeout 30 --max-time "$UPLOAD_TIMEOUT" --retry 2 --retry-delay 5 \
    "${UPLOAD_ARGS[@]}" "https://${SERVER}.gofile.io/uploadFile" \
    -o "$TEMP_FILE"; then
    error_exit "File upload failed! The file might be too large, the server is unavailable, your connection is too slow, or (if using -t/--token) the token was rejected."
fi

check_api_error "$TEMP_FILE" "uploading file"

# Parse the upload response
if ! LINK=$(jq -r '.data.downloadPage' "$TEMP_FILE" 2>"$STDERR_FILE"); then
    echo "Upload Response:" >&2
    cat "$TEMP_FILE" >&2
    echo "jq error:" >&2
    cat "$STDERR_FILE" >&2
    error_exit "Failed to parse upload response! The API might have returned unexpected data."
fi

if [[ -z "$LINK" || "$LINK" == "null" ]]; then
    echo "Upload Response:" >&2
    cat "$TEMP_FILE" >&2
    error_exit "Failed to retrieve download link! Check the API response above for details."
fi

# --- Success Output ---
echo ""
echo "✓ File uploaded successfully!"
echo "Download Link: $LINK"
echo ""
