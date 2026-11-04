#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail

# --- Script Information ---
# This script uploads one or more files to GoFile.io and displays the download link(s).
# Optimized for large files (e.g., compressed files, images, ROMs 1-4 GB).

VERSION="1.4.0"

# Seconds to wait between upload attempts (overridable, mainly for tests).
RETRY_DELAY="${GOFILE_RETRY_DELAY:-5}"

TEMP_FILE=""
STDERR_FILE=""

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
trap cleanup EXIT
# Ctrl-C / kill must exit non-zero (130 / 143), not reuse a stale $? of 0, so
# callers never mistake an interrupted upload for a success. `exit` still
# runs the EXIT trap above, which does the cleanup.
trap 'exit 130' INT
trap 'exit 143' TERM

# --- Argument Parsing ---
# Token can come from -t/--token, or the GOFILE_TOKEN env var (preferred for
# scripting, since it keeps the token out of shell history / process list).
TOKEN="${GOFILE_TOKEN:-}"
FILES=()
LIST_SERVERS=false
AUTO_FASTEST=false
CHOOSE_SERVER=false
FIRST_SERVER=false
QUIET=false
VERIFY=false
SINGLE_FOLDER=false
FOLDER_ID=""
RETRIES=3
LIMIT_RATE=""

# Quiet mode prints nothing but the download link(s) on stdout.
say()     { if [[ "$QUIET" != true ]]; then echo "$@"; fi; }
say_err() { if [[ "$QUIET" != true ]]; then echo "$@" >&2; fi; }

print_usage() {
    echo "GoFile Upload Script v${VERSION}"
    echo "Usage: $0 [options] <file_path> [file_path ...]"
    echo ""
    echo "  -t, --token TOKEN   GoFile account API token (ties the upload to your"
    echo "                      account instead of uploading as a guest)."
    echo "                      Can also be set via the GOFILE_TOKEN env var,"
    echo "                      which keeps it out of shell history. (The token is"
    echo "                      never passed to curl as a command-line argument,"
    echo "                      so it doesn't show up in 'ps' output either.)"
    echo "  -q, --quiet         No progress bar or messages: print only the download"
    echo "                      link(s) on stdout, e.g. LINK=\$($0 -q file.zip)"
    echo "  -r, --retries N     Upload attempts per file (default: 3). Each retry"
    echo "                      picks a fresh server."
    echo "  -c, --verify        Compute the local MD5 and compare it with the MD5"
    echo "                      GoFile reports for the uploaded file."
    echo "  -s, --single-folder Upload several files into one folder (they share one"
    echo "                      download link): files after the first are added to"
    echo "                      the folder the first upload created."
    echo "  --folder ID         Upload into an existing folder (needs a token)."
    echo "  --limit-rate RATE   Cap the upload speed, e.g. 5M or 500k (passed to curl)."
    echo "  --version           Show the version and exit."
    echo "  -h, --help          Show this help message."
    echo ""
    echo "  Server selection (default is --auto-fastest; adds a few seconds"
    echo "  up front to probe connection latency to each GoFile server):"
    echo "  --auto-fastest      (Default) Probe all servers and upload to the"
    echo "                      lowest-latency one. No need to pass this"
    echo "                      explicitly — it's used automatically when no"
    echo "                      other server-selection flag is given."
    echo "  --list-servers      List available servers ranked by latency and exit"
    echo "                      (no file required, no upload performed)."
    echo "  --choose-server     Probe all servers, show the ranked list, and"
    echo "                      prompt you to pick one interactively."
    echo "  --first-server      Skip probing entirely — use whichever server"
    echo "                      the GoFile API happens to list first (the old"
    echo "                      zero-overhead default from before v1.3.0)."
    echo ""
    echo "Find your token at: GoFile.io -> Account -> API Token"
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_usage
            exit 0
            ;;
        --version)
            echo "GoFile Upload Script v${VERSION}"
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
        -r|--retries)
            [[ -n "${2:-}" ]] || error_exit "Missing value for $1"
            RETRIES="$2"
            shift 2
            ;;
        --folder)
            [[ -n "${2:-}" ]] || error_exit "Missing value for $1"
            FOLDER_ID="$2"
            shift 2
            ;;
        --limit-rate)
            [[ -n "${2:-}" ]] || error_exit "Missing value for $1"
            LIMIT_RATE="$2"
            shift 2
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -c|--verify)
            VERIFY=true
            shift
            ;;
        -s|--single-folder)
            SINGLE_FOLDER=true
            shift
            ;;
        --list-servers)
            LIST_SERVERS=true
            shift
            ;;
        --auto-fastest)
            AUTO_FASTEST=true
            shift
            ;;
        --choose-server)
            CHOOSE_SERVER=true
            shift
            ;;
        --first-server)
            FIRST_SERVER=true
            shift
            ;;
        --)
            shift
            FILES+=("$@")
            break
            ;;
        -*)
            error_exit "Unknown option: $1 (use -h for help)"
            ;;
        *)
            FILES+=("$1")
            shift
            ;;
    esac
done

if [[ "${#FILES[@]}" -eq 0 && "$LIST_SERVERS" != true ]]; then
    print_usage >&2
    exit 1
fi

if ! [[ "$RETRIES" =~ ^[1-9][0-9]*$ ]]; then
    error_exit "-r/--retries must be a positive integer."
fi
if [[ -n "$LIMIT_RATE" ]] && ! [[ "$LIMIT_RATE" =~ ^[0-9]+[kKmMgG]?$ ]]; then
    error_exit "--limit-rate must look like 500k, 5M or 1G."
fi

# --- Server-selection mode resolution ---
# Only one of these makes sense at a time.
FLAG_COUNT=0
[[ "$LIST_SERVERS" == true ]] && FLAG_COUNT=$((FLAG_COUNT + 1))
[[ "$AUTO_FASTEST" == true ]] && FLAG_COUNT=$((FLAG_COUNT + 1))
[[ "$CHOOSE_SERVER" == true ]] && FLAG_COUNT=$((FLAG_COUNT + 1))
[[ "$FIRST_SERVER" == true ]] && FLAG_COUNT=$((FLAG_COUNT + 1))
if [[ "$FLAG_COUNT" -gt 1 ]]; then
    error_exit "Only one of --auto-fastest, --list-servers, --choose-server, --first-server may be used at a time."
fi

# As of v1.3.0, --auto-fastest is the default when no server-selection flag
# is given at all — probing costs a few seconds but generally lands on a
# closer/less congested server than blindly taking whatever the API lists
# first. --first-server restores the old zero-overhead behavior.
SERVER_MODE_IMPLICIT=false
if [[ "$FLAG_COUNT" -eq 0 ]]; then
    AUTO_FASTEST=true
    SERVER_MODE_IMPLICIT=true
fi

if [[ "$QUIET" == true && "$CHOOSE_SERVER" == true ]]; then
    error_exit "--choose-server needs to prompt you, so it can't be combined with -q/--quiet."
fi

SELECT_MODE=first
if [[ "$LIST_SERVERS" == true ]]; then
    SELECT_MODE=list
elif [[ "$AUTO_FASTEST" == true ]]; then
    SELECT_MODE=fastest
elif [[ "$CHOOSE_SERVER" == true ]]; then
    SELECT_MODE=choose
fi

# --- Dependency Check ---
# curl/jq are needed for every code path, including --list-servers (no file).
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        error_exit "Required command '$cmd' is not installed! Please install it."
    fi
done
if [[ "${#FILES[@]}" -gt 0 ]] && ! command -v stat &>/dev/null; then
    error_exit "Required command 'stat' is not installed! Please install it."
fi
if [[ "$VERIFY" == true ]] && ! command -v md5sum &>/dev/null && ! command -v md5 &>/dev/null; then
    error_exit "-c/--verify needs 'md5sum' (Linux) or 'md5' (macOS), and neither is installed."
fi

# --- File Existence and Readability Check ---
# Checked up front for every file, so a typo in the last argument doesn't
# waste a long upload of the first one. Empty list in --list-servers mode.
for f in "${FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        error_exit "File '$f' does not exist."
    elif [[ ! -r "$f" ]]; then
        error_exit "File '$f' exists but is not readable."
    fi
done

# Separate temp files for response body and stderr, so error output never
# leaks into the JSON we hand to jq.
TEMP_FILE=$(mktemp) || error_exit "Failed to create temporary file!"
STDERR_FILE=$(mktemp) || error_exit "Failed to create temporary file!"

# --- GoFile API helpers ---

# GoFile's API can return {"status":"error","message":"..."} — capture that
# message instead of just saying a field was missing/null.
# Returns 1 and sets API_ERROR_MSG if the response is an error envelope.
API_ERROR_MSG=""
check_api_error() {
    local resp_file="$1" context="$2" status msg
    # "|| true": the body may not be JSON at all (e.g. an HTML error page),
    # and under set -e a failing jq in an assignment would kill the script
    # silently before any error message is printed.
    status=$(jq -r '.status // empty' "$resp_file" 2>/dev/null) || true
    # Any status other than "ok" is an error (GoFile uses "error", "error-xxx", ...).
    if [[ -n "$status" && "$status" != "ok" ]]; then
        msg=$(jq -r '.message // .status' "$resp_file" 2>/dev/null) || msg="$status"
        API_ERROR_MSG="GoFile API error while $context: $msg"
        return 1
    fi
    return 0
}

file_md5() {
    if command -v md5sum &>/dev/null; then
        md5sum "$1" | cut -d' ' -f1
    else
        md5 -q "$1"
    fi
}

announce_mode() {
    if [[ "$SERVER_MODE_IMPLICIT" == true ]]; then
        say "No server-selection flag given — defaulting to --auto-fastest (use --first-server to skip probing)."
    elif [[ "$AUTO_FASTEST" == true ]]; then
        say "Using --auto-fastest as requested."
    elif [[ "$CHOOSE_SERVER" == true ]]; then
        say "Using --choose-server as requested."
    elif [[ "$FIRST_SERVER" == true ]]; then
        say "Using --first-server as requested (no latency probing)."
    fi
}

# Picks a GoFile server into $SERVER.
# mode: first | fastest | choose | list (list prints the table and exits).
# Returns 0 on success, 1 on a retryable failure, 2 on a fatal one.
select_server() {
    local mode="$1" name t line i ms choice fastest_line fastest_server
    local -a names unsorted ranked

    if ! curl -s --fail --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 2 \
        https://api.gofile.io/servers -o "$TEMP_FILE" 2>"$STDERR_FILE"; then
        echo "curl error output:" >&2
        cat "$STDERR_FILE" >&2
        echo "ERROR: Failed to connect to GoFile API! Please check your internet connection." >&2
        return 1
    fi

    if ! check_api_error "$TEMP_FILE" "fetching server list"; then
        echo "ERROR: $API_ERROR_MSG" >&2
        return 2
    fi

    if [[ "$mode" == first ]]; then
        # No probing, just take the first listed server.
        if ! SERVER=$(jq -r '.data.servers[0].name' "$TEMP_FILE" 2>"$STDERR_FILE"); then
            echo "API Response:" >&2
            cat "$TEMP_FILE" >&2
            echo "jq error:" >&2
            cat "$STDERR_FILE" >&2
            echo "ERROR: Failed to parse GoFile API response! The API might have returned unexpected data." >&2
            return 2
        fi
        if [[ -z "$SERVER" || "$SERVER" == "null" ]]; then
            echo "API Response:" >&2
            cat "$TEMP_FILE" >&2
            echo "ERROR: Failed to retrieve valid server name from GoFile API! No servers available." >&2
            return 2
        fi
        return 0
    fi

    # while-read instead of mapfile: mapfile needs bash 4+, but macOS ships 3.2.
    names=()
    while IFS= read -r name; do
        names+=("$name")
    done < <(jq -r '.data.servers[].name' "$TEMP_FILE" 2>"$STDERR_FILE")
    if [[ "${#names[@]}" -eq 0 || -z "${names[0]}" ]]; then
        echo "API Response:" >&2
        cat "$TEMP_FILE" >&2
        echo "ERROR: Failed to retrieve any server names from GoFile API." >&2
        return 2
    fi

    say_err "Probing ${#names[@]} GoFile server(s) for connection latency..."

    # EXPERIMENTAL: this measures TCP connect time only (how fast a
    # connection opens), not actual upload throughput. It's a reasonable
    # proxy for "closest/least congested server" but it is not a guarantee
    # of the fastest transfer — real upload speed also depends on your own
    # uplink bandwidth, which no server choice can get around.
    unsorted=()
    for name in "${names[@]}"; do
        t=$(curl -o /dev/null -s -w '%{time_connect}' --connect-timeout 2 --max-time 4 \
            "https://${name}.gofile.io/" 2>/dev/null) || t=""
        [[ -z "$t" ]] && t="9999"
        unsorted+=("$t $name")
    done
    ranked=()
    while IFS= read -r line; do
        ranked+=("$line")
    done < <(printf '%s\n' "${unsorted[@]}" | sort -n)

    if [[ "$mode" == list || "$mode" == choose ]]; then
        echo ""
        printf "  %-4s %-16s %s\n" "#" "SERVER" "CONNECT TIME"
        i=0
        for line in "${ranked[@]}"; do
            i=$((i + 1))
            t="${line%% *}"
            name="${line#* }"
            if [[ "$t" == "9999" ]]; then
                printf "  %-4s %-16s %s\n" "$i)" "$name" "unreachable"
            else
                ms=$(awk -v s="$t" 'BEGIN { printf "%.0f", s * 1000 }')
                printf "  %-4s %-16s %sms\n" "$i)" "$name" "$ms"
            fi
        done
        echo ""
    fi

    if [[ "$mode" == list ]]; then
        exit 0
    fi

    fastest_line="${ranked[0]}"
    fastest_server="${fastest_line#* }"
    if [[ "${fastest_line%% *}" == "9999" ]]; then
        # Every probe failed (probe blocked, flaky network...): don't pretend
        # one of them is "fastest"; fall back to the server the API listed first.
        echo "WARNING: no server answered the latency probe; using the first server GoFile listed (${names[0]})." >&2
        fastest_server="${names[0]}"
    fi

    if [[ "$mode" == choose ]]; then
        if [[ -t 0 ]]; then
            read -rp "Select a server [1-${#ranked[@]}] (default 1, fastest): " choice
            choice="${choice:-1}"
            if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#ranked[@]} )); then
                echo "ERROR: Invalid selection: $choice" >&2
                return 2
            fi
            line="${ranked[$((choice - 1))]}"
            SERVER="${line#* }"
        else
            echo "Not running interactively — using fastest server (${fastest_server})." >&2
            SERVER="$fastest_server"
        fi
    else
        SERVER="$fastest_server"
    fi
    return 0
}

# --- Upload ---
SERVER=""
LINK=""
FIRST_LINK=""
MODE_ANNOUNCED=false

# Uploads one file and sets LINK on success. Returns 0 on success, 1 on failure
# (the reason has already been printed to stderr).
upload_one() {
    local file="$1"
    local name size esc attempt mode sel_rc curl_rc http_code api_failed ui cfg esc_token
    local remote_md5 local_md5 parent new_token
    local -a args

    name=$(basename "$file")
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null) || true
    if [[ -z "$size" ]]; then
        echo "ERROR: Could not determine file size for '$file'." >&2
        return 1
    fi

    say "File: $name"
    say "Size: $(du -h "$file" | cut -f1)"
    if [[ -n "$TOKEN" ]]; then
        say "Account: authenticated (token supplied)"
    else
        say "Account: guest (no token — file will be shorter-lived; pass -t/--token to upload to your account)"
    fi
    say ""

    # Escape \ and " and wrap in quotes so curl's -F parser accepts file names
    # containing ; , or quotes.
    esc=${file//\\/\\\\}
    esc=${esc//\"/\\\"}

    # Form fields first, file last: a streaming server needs to see the
    # destination folder before the file data arrives.
    args=()
    # The token reaches curl through a config on stdin (-K -), NOT as -H /
    # --form-string arguments: command-line arguments are readable by every user
    # via ps and /proc, which matters on shared build servers.
    # form-string sends it literally (plain -F treats a leading @ or < specially).
    # GoFile's own docs are inconsistent about whether the token is expected as
    # a form field or an Authorization header, so we send both.
    cfg=""
    if [[ -n "$TOKEN" ]]; then
        esc_token=${TOKEN//\\/\\\\}
        esc_token=${esc_token//\"/\\\"}
        cfg="header = \"Authorization: Bearer ${esc_token}\""$'\n'"form-string = \"token=${esc_token}\""$'\n'
        args+=(-K -)
    fi
    if [[ -n "$FOLDER_ID" ]]; then
        args+=(--form-string "folderId=${FOLDER_ID}")
    fi
    args+=(-F "file=@\"${esc}\"")
    if [[ -n "$LIMIT_RATE" ]]; then
        args+=(--limit-rate "$LIMIT_RATE")
    fi

    if [[ "$QUIET" == true ]]; then ui=-sS; else ui=-#; fi

    for (( attempt = 1; attempt <= RETRIES; attempt++ )); do
        mode=""
        if [[ "$attempt" -gt 1 ]]; then
            # A failed attempt may well be the server's fault: pick again.
            echo "Retrying in ${RETRY_DELAY}s (attempt ${attempt} of ${RETRIES})..." >&2
            sleep "$RETRY_DELAY"
            if [[ "$FIRST_SERVER" == true ]]; then mode=first; else mode=fastest; fi
        elif [[ -z "$SERVER" ]]; then
            mode="$SELECT_MODE"
        fi

        if [[ -n "$mode" ]]; then
            say "Fetching best GoFile server..."
            if [[ "$MODE_ANNOUNCED" != true ]]; then
                announce_mode
                MODE_ANNOUNCED=true
            fi
            sel_rc=0
            select_server "$mode" || sel_rc=$?
            if [[ "$sel_rc" -eq 2 ]]; then return 1; fi
            if [[ "$sel_rc" -ne 0 ]]; then continue; fi
            say "Using GoFile server: ${SERVER}"
            say ""
        fi

        if [[ "$attempt" -eq 1 ]]; then
            say "Uploading file '$name' to GoFile..."
            if [[ "$size" -gt 3221225472 ]]; then  # >3GB
                say "This is a very large file - upload may take 15-60+ minutes..."
            elif [[ "$size" -gt 1073741824 ]]; then  # >1GB
                say "This is a large file - upload may take 10-30 minutes..."
            elif [[ "$size" -gt 524288000 ]]; then  # >500MB
                say "This may take 5-10 minutes..."
            else
                say "Uploading..."
            fi
            say ""
        fi

        # No --max-time: any fixed cap eventually kills a slow-but-healthy upload
        # (e.g. ~1GB on a ~12 Mbps uplink needs more than 10 min). Abort only if
        # the transfer stalls (< 1 KB/s for 120 s). No --fail either: with it curl
        # drops the response body on HTTP 4xx/5xx, hiding GoFile's actual error.
        # No curl --retry: the loop here retries the whole thing on a fresh server.
        curl_rc=0
        http_code=$(curl "$ui" --connect-timeout 30 --speed-limit 1024 --speed-time 120 \
            "${args[@]}" "https://${SERVER}.gofile.io/uploadFile" \
            -o "$TEMP_FILE" -w '%{http_code}' <<<"$cfg") || curl_rc=$?
        if [[ "$curl_rc" -ne 0 ]]; then
            echo "WARNING: upload failed (curl exit code ${curl_rc}); the server may be unavailable, the connection may have stalled, or it was lost." >&2
            continue
        fi
        [[ "$http_code" =~ ^[0-9]+$ ]] || http_code=0

        api_failed=false
        check_api_error "$TEMP_FILE" "uploading file" || api_failed=true

        # Server-side trouble and rate limits are worth another try; anything else
        # (bad token, bad request) won't fix itself.
        if [[ "$http_code" -ge 500 || "$http_code" -eq 429 ]]; then
            if [[ "$api_failed" == true ]]; then
                echo "WARNING: $API_ERROR_MSG (HTTP ${http_code})" >&2
            else
                echo "WARNING: GoFile returned HTTP ${http_code}." >&2
                head -c 500 "$TEMP_FILE" >&2
                echo >&2
            fi
            continue
        fi
        if [[ "$api_failed" == true ]]; then
            echo "ERROR: $API_ERROR_MSG" >&2
            return 1
        fi
        if [[ "$http_code" -ge 400 ]]; then
            echo "Upload Response:" >&2
            head -c 500 "$TEMP_FILE" >&2
            echo >&2
            echo "ERROR: GoFile rejected the upload (HTTP ${http_code}). If using -t/--token, check that the token is valid." >&2
            return 1
        fi

        # Parse the upload response
        if ! LINK=$(jq -r '.data.downloadPage' "$TEMP_FILE" 2>"$STDERR_FILE"); then
            echo "Upload Response:" >&2
            cat "$TEMP_FILE" >&2
            echo "jq error:" >&2
            cat "$STDERR_FILE" >&2
            echo "ERROR: Failed to parse upload response! The API might have returned unexpected data." >&2
            return 1
        fi
        if [[ -z "$LINK" || "$LINK" == "null" ]]; then
            echo "Upload Response:" >&2
            cat "$TEMP_FILE" >&2
            echo "ERROR: Failed to retrieve download link! Check the API response above for details." >&2
            return 1
        fi

        if [[ "$VERIFY" == true ]]; then
            local_md5=$(file_md5 "$file" | tr 'A-F' 'a-f')
            remote_md5=$(jq -r '.data.md5 // empty' "$TEMP_FILE" 2>/dev/null | tr 'A-F' 'a-f') || remote_md5=""
            say "MD5 (local): ${local_md5}"
            if [[ -z "$remote_md5" ]]; then
                echo "WARNING: GoFile returned no MD5 for this file, so it can't be verified." >&2
            elif [[ "$local_md5" != "$remote_md5" ]]; then
                echo "ERROR: MD5 mismatch for '$name': local ${local_md5}, GoFile ${remote_md5}. The upload may be corrupted." >&2
                return 1
            else
                say "✓ MD5 verified"
            fi
        fi

        # -s: the first upload creates a folder (for a guest, a brand-new one);
        # later files are sent into it with the matching token + folder id.
        if [[ "$SINGLE_FOLDER" == true && -z "$FOLDER_ID" ]]; then
            parent=$(jq -r '.data.parentFolder // empty' "$TEMP_FILE" 2>/dev/null) || parent=""
            new_token=$(jq -r '.data.guestToken // empty' "$TEMP_FILE" 2>/dev/null) || new_token=""
            if [[ -z "$TOKEN" ]]; then TOKEN="$new_token"; fi
            if [[ -z "$parent" || -z "$TOKEN" ]]; then
                echo "WARNING: GoFile's response has no folder id/token to reuse, so the remaining files will be uploaded separately." >&2
                SINGLE_FOLDER=false
            else
                FOLDER_ID="$parent"
            fi
        fi
        return 0
    done

    echo "ERROR: Upload of '$name' failed after ${RETRIES} attempt(s)." >&2
    return 1
}

# --- Main ---
if [[ "$LIST_SERVERS" == true ]]; then
    say "Fetching best GoFile server..."
    # select_server exits 0 itself after printing the table; returning means failure.
    select_server list || true
    exit 1
fi

failed=0
for f in "${FILES[@]}"; do
    if upload_one "$f"; then
        if [[ -z "$FIRST_LINK" ]]; then FIRST_LINK="$LINK"; fi
        if [[ "$QUIET" == true ]]; then
            # With -s every file shares one link: print it once, at the end.
            if [[ "$SINGLE_FOLDER" != true ]]; then echo "$LINK"; fi
        else
            echo ""
            echo "✓ File uploaded successfully!"
            echo "Download Link: $LINK"
            echo ""
        fi
    else
        failed=$((failed + 1))
    fi
done

if [[ "$QUIET" == true && "$SINGLE_FOLDER" == true && -n "$FIRST_LINK" ]]; then
    echo "$FIRST_LINK"
fi

if [[ "$failed" -gt 0 ]]; then
    if [[ "${#FILES[@]}" -gt 1 ]]; then
        echo "ERROR: ${failed} of ${#FILES[@]} upload(s) failed." >&2
    fi
    exit 1
fi
