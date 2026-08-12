# GoFile Upload Script

A robust bash script to upload files to GoFile.io with automatic latency-based server selection and download link generation. Optimized for large files (1-4 GB) with smart progress indicators and comprehensive error handling.

## Features

- ✅ **Fastest-Server Selection (default)** - Probes all available GoFile servers by connection latency and automatically uploads to the closest/least congested one
- ✅ **Smart File Detection** - Automatically detects file size and shows appropriate upload time estimates
- ✅ **Memory Optimized** - Uses temporary files to handle large uploads without consuming excessive RAM
- ✅ **Optional Account Upload** - Supply your GoFile API token to tie uploads to your account instead of uploading as a guest
- ✅ **Retry on Transient Failures** - Automatically retries the server-list and upload requests on connection hiccups
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

- `bash` (4.0+)
- `curl` - For making HTTP requests
- `jq` - For parsing JSON responses
- `stat` - For determining file size (present by default on Linux/macOS, and inside WSL)

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
Usage: upload.sh [-t TOKEN] [server-selection flag] <file_path>

  -t, --token TOKEN   GoFile account API token (ties the upload to your
                      account instead of uploading as a guest).
                      Can also be set via the GOFILE_TOKEN env var,
                      which avoids the token showing up in shell
                      history or 'ps' output.
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

### "File upload failed"

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

1. Parses arguments (file path, optional token, optional server-selection flag)
2. Validates file existence and readability
3. Checks for required dependencies
4. Queries the GoFile API for the list of available servers
5. Selects a server — probing all of them by latency and picking the fastest (default), letting you choose interactively, listing them without uploading, or skipping probing entirely, depending on flags
6. Uploads the file with progress tracking, optionally authenticated with your token
7. Extracts and displays the download link, or GoFile's error message on failure

### Memory Usage

- Small files (< 500MB): Minimal memory usage
- Large files (1-4GB): Uses temporary files to avoid high RAM consumption
- Peak memory: ~50MB regardless of file size

### Security

- API token (if provided) is only ever passed directly to `curl` — never echoed, logged, or written to any file by this script
- Files are uploaded directly to GoFile's servers
- Temporary files are automatically cleaned up, including on Ctrl-C or crash
- No data is stored locally after upload

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for the full version history.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This script is provided as-is under the MIT License.

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
