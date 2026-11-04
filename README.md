# GoFile Upload Script

A robust bash script to upload files to GoFile.io with automatic latency-based server selection and download link generation. Optimized for large files (1-4 GB) with smart progress indicators and comprehensive error handling.

## Features

- ✅ **Fastest-Server Selection (default)** - Probes all available GoFile servers by connection latency and automatically uploads to the closest/least congested one
- ✅ **Smart File Detection** - Automatically detects file size and shows appropriate upload time estimates
- ✅ **Large-File Friendly** - Streams the file straight from disk (the temp files only hold small JSON responses) and has no fixed time limit: an upload is aborted only if the transfer stalls (under 1 KB/s for 120 s)
- ✅ **Optional Account Upload** - Supply your GoFile API token to tie uploads to your account instead of uploading as a guest
- ✅ **Retries** - Retries a failed upload (default 3 attempts, `-r N`), picking a fresh server each time; client errors such as a rejected token are not retried
- ✅ **Multiple Files** - Upload several files in one run, optionally into one shared folder (`-s`) or an existing one (`--folder`)
- ✅ **Script-Friendly** - `-q` prints only the download link on stdout, so `LINK=$(./upload.sh -q file.zip)` just works
- ✅ **Optional Integrity Check** - `-c` compares the local MD5 with the one GoFile reports
- ✅ **Token Stays Private** - Your API token is handed to curl on stdin, never as a command-line argument, so it isn't visible in `ps`
- ✅ **Progress Tracking** - Shows upload progress with a visual progress bar
- ✅ **Robust Error Handling** - Comprehensive checks with detailed error messages, including GoFile's own API error responses
- ✅ **Automatic Cleanup** - Removes temporary files even if the script crashes or is interrupted (Ctrl-C)
- ⚠️ **Linux and macOS only** - not natively supported on Windows; see [Supported Operating Systems](#supported-operating-systems) below

## Supported Operating Systems

| OS | Supported | Notes |
|---|---|---|
| Linux | ✅ Yes | Primary target platform |
| macOS | ✅ Yes | Uses the `stat -f%z` fallback for file size |
| Windows (native) | ❌ No | This is a bash script — it will **not** run in cmd.exe or PowerShell as-is |
| Windows via WSL | ✅ Yes | Works like a normal Linux install — see below |

### Windows Users: Use WSL

This script does not run natively on Windows. If you're on Windows, install **WSL (Windows Subsystem for Linux)**, which gives you a real Linux environment to run it in exactly as documented in this README:

```powershell
wsl --install
```

Then open the WSL terminal (e.g. Ubuntu) and install the dependencies as normal:
```bash
sudo apt update
sudo apt install curl jq
```

From there, follow the Linux instructions below — everything works the same inside WSL, including file paths like `/mnt/c/Users/YourName/Downloads/file.zip` for accessing files on your Windows drives.

> A native Windows (PowerShell/batch) version is not currently planned in the near term — batch scripting is too limited for this script's JSON parsing and error handling, and a proper port would likely need to be written in PowerShell as a separate effort rather than a quick translation. WSL is the recommended path for Windows users until/unless that happens.

## Requirements

- `bash` (3.2+, so the macOS default works)
- `curl` - For making HTTP requests
- `jq` - For parsing JSON responses
- `stat` - For determining file size (present by default on Linux/macOS, and inside WSL)
- `md5sum` (Linux) or `md5` (macOS) - only needed for `-c`/`--verify`

### Installing Dependencies

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install curl jq
```

**macOS:**
```bash
brew install curl jq
```

**Fedora/RHEL:**
```bash
sudo dnf install curl jq
```

**Arch Linux:**
```bash
sudo pacman -S curl jq
```

## Installation

There are two common ways to use this script — pick whichever fits your workflow.

### Option A: Download and Keep Locally (recommended)

Best if you'll be uploading files regularly, want to inspect the script before running it, or want to use `-h`/`--help` and version info without re-downloading each time.

```bash
curl -o upload.sh https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh
chmod +x upload.sh
```

Then run it from wherever you downloaded it:
```bash
./upload.sh /path/to/your/file.zip
```

**Install it globally** (so you can run `gofile-upload` from any directory):
```bash
sudo curl -o /usr/local/bin/gofile-upload https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh
sudo chmod +x /usr/local/bin/gofile-upload
gofile-upload /path/to/file.zip
```

### Option B: Run Directly via `curl | bash` (no download step)

Convenient for one-off uploads or CI scripts, at the cost of trusting whatever is currently at that URL — you're piping a remote script straight into `bash` without inspecting it first. If that matters to you, use Option A instead.

```bash
curl -s https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh | bash -s -- /path/to/your/file.zip
```

Flags work the same way — put them after `-s --`:
```bash
curl -s https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh | bash -s -- --list-servers
curl -s https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh | bash -s -- -t "$GOFILE_TOKEN" backup.tar.gz
```

> **Note:** `--choose-server` (the interactive picker) works fine over `curl | bash` too, as long as you're running it in an actual terminal — the script detects whether stdin is interactive and falls back to the fastest server automatically if it isn't (e.g. if you're running this from a non-interactive script or cron job).

## Usage

```
GoFile Upload Script v1.4.0
Usage: upload.sh [options] <file_path> [file_path ...]

  -t, --token TOKEN   GoFile account API token (ties the upload to your
                      account instead of uploading as a guest).
                      Can also be set via the GOFILE_TOKEN env var,
                      which keeps it out of shell history. (The token is
                      never passed to curl as a command-line argument,
                      so it doesn't show up in 'ps' output either.)
  -q, --quiet         No progress bar or messages: print only the download
                      link(s) on stdout, e.g. LINK=$(upload.sh -q file.zip)
  -r, --retries N     Upload attempts per file (default: 3). Each retry
                      picks a fresh server.
  -c, --verify        Compute the local MD5 and compare it with the MD5
                      GoFile reports for the uploaded file.
  -s, --single-folder Upload several files into one folder (they share one
                      download link): files after the first are added to
                      the folder the first upload created.
  --folder ID         Upload into an existing folder (needs a token).
  --limit-rate RATE   Cap the upload speed, e.g. 5M or 500k (passed to curl).
  --version           Show the version and exit.
  -h, --help          Show this help message.

  Server selection (default is --auto-fastest; adds a few seconds
  up front to probe connection latency to each GoFile server):
  --auto-fastest      (Default) Probe all servers and upload to the
                      lowest-latency one. No need to pass this
                      explicitly — it's used automatically when no
                      other server-selection flag is given.
  --list-servers      List available servers ranked by latency and exit
                      (no file required, no upload performed).
  --choose-server     Probe all servers, show the ranked list, and
                      prompt you to pick one interactively.
  --first-server      Skip probing entirely — use whichever server
                      the GoFile API happens to list first (the old
                      zero-overhead default from before v1.3.0).

Find your token at: GoFile.io -> Account -> API Token
```

### Basic Usage

Just point it at a file — as of v1.3.0, it automatically probes and uploads to the fastest available server:

```bash
./upload.sh /path/to/your/file.zip
```

### Server Selection

**See which server is fastest from your connection, without uploading anything:**
```bash
./upload.sh --list-servers
```
```
Probing 13 GoFile server(s) for connection latency...
  #    SERVER           CONNECT TIME
  1)   store1           166ms
  2)   store-eu-par-8   176ms
  3)   store-eu-par-6   179ms
  ...
```

**Pick a server yourself, interactively:**
```bash
./upload.sh --choose-server backup.tar.gz
```

**Skip probing entirely (old default, zero extra overhead):**
```bash
./upload.sh --first-server backup.tar.gz
```

> **What the latency probe actually measures:** TCP connect time to each server — a reasonable proxy for "closest / least congested," similar in spirit to a ping. It is *not* a guarantee of the fastest transfer speed; your actual upload throughput is still capped by your own internet uplink bandwidth, which no server choice can change. On most connections the difference between servers is a modest latency improvement, not a dramatic speed boost.

### Uploading to Your GoFile Account (Optional)

By default, files are uploaded as a guest — GoFile applies shorter retention and lower rate limits to guest uploads. If you have a GoFile account, pass your API token to tie the upload to it:

```bash
./upload.sh -t YOUR_GOFILE_TOKEN backup.tar.gz
```

Or, preferred for scripting since it keeps the token out of shell history and `ps` output:

```bash
export GOFILE_TOKEN=YOUR_GOFILE_TOKEN
./upload.sh backup.tar.gz
```

Find your token at: **GoFile.io → Account → API Token**. Treat it like a password — anyone with it can upload to (and potentially manage content in) your account.

> **Note on GoFile's API docs:** publicly available documentation is inconsistent about whether the token should be sent as a form field or an `Authorization: Bearer` header. This script sends it both ways so it works regardless of which one GoFile's current backend actually reads. If your token is rejected, the script shows GoFile's own error message rather than a generic parse failure.

### Multiple Files, Scripting, Retries and Verification

**Upload several files in one run** (each gets its own link):
```bash
./upload.sh lineage.zip boot.img vendor_boot.img
```

**Put them all in one folder so they share a single link:**
```bash
./upload.sh -s lineage.zip boot.img vendor_boot.img
```
The first upload creates the folder; the remaining files are added to it. (If GoFile's response doesn't include a folder id, the script warns and uploads the rest separately.) With an account token you can also target an existing folder with `--folder FOLDER_ID`.

**Use it from scripts** — `-q` suppresses the progress bar and messages and prints only the link on stdout (errors still go to stderr, and the exit code is non-zero on failure):
```bash
LINK=$(./upload.sh -q rom.zip) || exit 1
echo "Download: $LINK"
```

**Retries:** a failed upload is retried up to 3 times by default, each time on a freshly picked server. Change it with `-r`:
```bash
./upload.sh -r 5 backup.tar.gz
```

**Verify the upload** — compares the MD5 of the local file with the one GoFile reports (computing the MD5 of a multi-GB file takes a few seconds):
```bash
./upload.sh -c rom.zip
```

**Don't saturate your connection:**
```bash
./upload.sh --limit-rate 5M rom.zip
```

### More Examples

**Upload a custom ROM (auto-fastest by default):**
```bash
./upload.sh lineage-20-pixel6-4.2GB.zip
```

**Upload a compressed archive to your account, skipping the latency probe:**
```bash
./upload.sh -t YOUR_TOKEN --first-server backup.tar.gz
```

**Upload via `curl | bash` with a token from an env var:**
```bash
curl -s https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh | bash -s -- -t "$GOFILE_TOKEN" recording.mp4
```

## Output Example

```
File: lineage-22.2-20260809-UNOFFICIAL-sapphire.zip
Size: 2.1G
Account: guest (no token — file will be shorter-lived; pass -t/--token to upload to your account)

Fetching best GoFile server...
No server-selection flag given — defaulting to --auto-fastest (use --first-server to skip probing).
Probing 13 GoFile server(s) for connection latency...
Using GoFile server: store1

Uploading file 'lineage-22.2-20260809-UNOFFICIAL-sapphire.zip' to GoFile...
This is a large file - upload may take 10-30 minutes...

######################################################################## 100.0%

✓ File uploaded successfully!
Download Link: https://gofile.io/d/abc123
```

## Upload Time Estimates

- **< 500MB**: Quick upload (seconds to minutes)
- **500MB - 1GB**: A few minutes
- **1GB - 3GB**: 10-30 minutes
- **> 3GB**: 15-60+ minutes (depending on connection speed)

These are rough estimates based on file size alone — your actual time depends heavily on your upload bandwidth (see the note on server selection above).

## Error Handling

The script includes comprehensive error handling for:

- ❌ Missing or unreadable files
- ❌ Missing dependencies (curl, jq, stat)
- ❌ GoFile API connection failures (with automatic retry)
- ❌ GoFile API error responses (e.g. an invalid token), surfaced with GoFile's own error message
- ❌ Server selection issues, including all probed servers being unreachable
- ❌ Upload failures
- ❌ Invalid API responses
- ❌ Conflicting server-selection flags (e.g. `--auto-fastest --first-server` together)

All errors provide detailed messages to help troubleshoot issues. Temporary files are always cleaned up, even on Ctrl-C or an unexpected crash.

## Troubleshooting

### "Command not found: curl", "jq", or "stat"

Install the missing dependency using your package manager (see Requirements section).

### "Failed to connect to GoFile API"

- Check your internet connection
- Verify GoFile.io is accessible from your network
- The script already retries automatically 3 times on this step — if it still fails, try again after a few minutes

### "GoFile API error while ..."

This means GoFile's API responded successfully but reported an error (for example, an invalid or expired token). The message shown is GoFile's own error text — check it for the specific cause.

### "Upload of '...' failed after N attempt(s)"

- The script already retried on fresh servers (3 attempts by default) — raise it with `-r 5` if your connection is flaky
- Ensure the file is not corrupted
- Check if the file size exceeds GoFile's limits
- Verify you have sufficient internet bandwidth
- If using `-t`/`--token`, the token may have been rejected — try without it to confirm

### Upload seems stuck / no progress showing

The progress bar (`#####`) writes to the terminal directly. If you don't see it moving for a large file, it's very likely still working — GoFile's servers can be slow to acknowledge multi-GB uploads. Give it a few minutes before assuming it's hung; if you interrupt with Ctrl-C, temporary files are cleaned up automatically.

### Upload is very slow

- Large files naturally take longer
- Try `--list-servers` to check whether a closer server is available, then upload with `--auto-fastest` (the default) or manually with `--choose-server`
- Check your upload speed:
```bash
sudo apt install speedtest-cli
speedtest-cli
```
- Consider uploading during off-peak hours

## Technical Details

### How It Works

1. Parses arguments (file path(s), optional token, optional server-selection flag, other options)
2. Validates every file's existence and readability up front, and checks for required dependencies
3. Queries the GoFile API for the list of available servers
4. Selects a server — probing all of them by latency and picking the fastest (default), letting you choose interactively, listing them without uploading, or skipping probing entirely, depending on flags
5. Uploads each file with progress tracking, optionally authenticated with your token; a failed attempt is retried on a fresh server
6. Checks the API's response, optionally verifies the MD5, and prints the download link — or GoFile's own error message on failure

### Memory Usage

curl streams the file straight from disk, so memory use stays small no matter how big the file is. The script's temporary files only hold small JSON responses and error text.

### Security

- API token (if provided) is handed to `curl` through a config on stdin — never as a command-line argument (so it isn't visible in `ps` or `/proc` to other users), and never echoed, logged, or written to any file by this script
- Files are uploaded directly to GoFile's servers
- Temporary files are automatically cleaned up, including on Ctrl-C or crash
- No data is stored locally after upload

## Development

`test/run.sh` runs the script against a small fake GoFile API (no network, nothing is really uploaded) and checks retries, error handling, token privacy, multi-file uploads and more. It needs `bash`, `curl`, `jq` and `python3`:

```bash
bash test/run.sh
```

The same test, plus ShellCheck, runs on every push via GitHub Actions.

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for the full version history.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This is a fork of [Sushrut1101/GoFile-Upload](https://github.com/Sushrut1101/GoFile-Upload).
The upstream project does not currently declare a license, so no license is granted here
either. All rights to the original work remain with its author.

## Acknowledgments

- [GoFile.io](https://gofile.io) - Free file hosting service
- Built with `curl` and `jq`

## Support

If you encounter any issues or have questions:

1. Check the Troubleshooting section
2. Open an issue on GitHub
3. Ensure you're using the latest version of the script

### Credits

- <https://gofile.io> - For the Amazing Website to upload Unlimited files with Unlimited filesize to fast servers, for free!
- [Sushrut1101](https://github.com/Sushrut1101) - To make the original Script

---

**Note:** GoFile.io may have file size limits and retention policies. Check their website for current limitations. GoFile's API is also documented inconsistently across sources at time of writing — if an endpoint or auth method appears to have changed, please open an issue.
