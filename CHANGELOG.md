# Changelog

All notable changes to this script are documented here.

## [1.2.0]

### Added
- Optional GoFile account authentication: `-t TOKEN` / `--token TOKEN` / `--token=TOKEN` flag, or `GOFILE_TOKEN` environment variable. Uploads as guest if omitted.
- Token is sent both as a `token` form field and an `Authorization: Bearer` header on the upload request, since publicly available GoFile API docs disagree on which one is read.
- `check_api_error` helper: detects GoFile's `{"status":"error","message":"..."}` response envelope and surfaces the actual API error message (e.g. an invalid token) instead of a generic "failed to parse response" error.
- Output now states whether the upload is authenticated or guest before the transfer starts.
- `--help` output documents the new token flag and where to find your token on GoFile.

### Fixed
- **Exit code bug in the cleanup trap:** the `EXIT`/`INT`/`TERM` trap's own `[[ ]]` file-existence checks were overwriting `$?`, so the script could report a failure exit code (e.g. after `-h`/`--help`) even when it had completed successfully. The trap now captures and re-exits with the original status.

## [1.1.0]

### Fixed
- **stderr/stdout contamination bug:** the server-list fetch and its `jq` parse previously used `2>&1`, which could mix curl/jq error text into the value captured by `$(...)`. This could corrupt the `$SERVER` variable or the JSON handed to `jq`, causing the "no server available" check to behave unpredictably or JSON parsing to fail for reasons unrelated to the actual API response. Error output is now written to a dedicated temp file and only shown to the user on failure.
- `FILE_SIZE_BYTES` is now explicitly checked for empty/failure rather than silently continuing if both `stat -f%z` (macOS) and `stat -c%s` (Linux) fail.

### Added
- `curl --retry` on both the server-list fetch (3 retries) and the upload itself (2 retries) to tolerate transient connection failures. Note this only helps at connection-establishment — a drop mid-transfer still requires restarting the upload.
- `set -o pipefail` alongside the existing `set -e`.
- `-h` / `--help` flag and a version string, useful since the script is often run via `curl | bash` with no other way to check what version is running.
- `stat` added to the explicit dependency check (previously only `curl`/`jq` were checked, even though `stat` was required).
- Trap now also handles `INT`/`TERM` signals (e.g. Ctrl-C), not just normal `EXIT`, so temp files are cleaned up on interruption too.

### Notes
- An intermediate build of this version accidentally redirected the upload's `curl -#` progress-bar output (written to stderr) into the same error-log file used for the API calls, which hid the visible progress bar during large uploads. This was corrected before release — progress bar output goes to the terminal as before, since that curl call's output was never captured into a variable and so never had the contamination risk the stderr fix was addressing.

## [1.0.0] — baseline (forked from Sushrut1101/GoFile-Upload)

- Automatic GoFile server selection via `api.gofile.io/servers`
- Upload with progress bar via `curl -#`
- File size detection and upload time estimates
- Temporary-file-based upload to avoid high memory usage on large files
- Basic error handling and cleanup on exit
