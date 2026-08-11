# GoFile Upload Script

A robust bash script to upload files to GoFile.io with automatic server selection and download link generation. Optimized for large files (1-4 GB) with smart progress indicators and comprehensive error handling.

## Features

- ✅ **Smart File Detection** - Automatically detects file size and shows appropriate upload time estimates
- ✅ **Memory Optimized** - Uses temporary files to handle large uploads without consuming excessive RAM
- ✅ **Automatic Server Selection** - Queries GoFile API to find the best available server
- ✅ **Progress Tracking** - Shows upload progress with visual progress bar
- ✅ **Optional Account Upload** - Supply your GoFile API token to tie uploads to your account instead of uploading as a guest
- ✅ **Retry on Transient Failures** - Automatically retries the server-list and upload requests on connection hiccups
- ✅ **Robust Error Handling** - Comprehensive checks with detailed error messages, including GoFile's own API error responses
- ✅ **Automatic Cleanup** - Removes temporary files even if the script crashes or is interrupted (Ctrl-C)
- ✅ **Cross-Platform** - Works on Linux and macOS

## Requirements

- `bash` (4.0+)
- `curl` - For making HTTP requests
- `jq` - For parsing JSON responses
- `stat` - For determining file size (present by default on Linux/macOS)

### Installing Dependencies

**Ubuntu/Debian:**
```
sudo apt update
sudo apt install curl jq
```

**macOS:**
```
brew install curl jq
```

**Fedora/RHEL:**
```
sudo dnf install curl jq
```

**Arch Linux:**
```
sudo pacman -S curl jq
```

## Installation

### Method 1: Download the Script

```
curl -o upload.sh https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh
chmod +x upload.sh
```

### Method 2: Quick Use (Without Downloading)

```
curl -s https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh | bash -s -- /path/to/your/file.zip
```

> **Note:** piping a remote script straight into `bash` means you're trusting whatever's currently at that URL. Prefer Method 1 (download, inspect, then run) if that matters to you.

### Method 3: Install Globally

```
sudo curl -o /usr/local/bin/gofile-upload https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh
sudo chmod +x /usr/local/bin/gofile-upload
gofile-upload /path/to/file.zip
```

## Usage

### Basic Usage

```
./upload.sh [-t TOKEN] <file_path>
```

```
./upload.sh --help
```

### Uploading to Your GoFile Account (Optional)

By default, files are uploaded as a guest — GoFile applies shorter retention and lower rate limits to guest uploads. If you have a GoFile account, you can pass your API token to tie the upload to it:

```
./upload.sh -t YOUR_GOFILE_TOKEN backup.tar.gz
```

Or, preferred for scripting since it avoids the token showing up in shell history or `ps` output:

```
export GOFILE_TOKEN=YOUR_GOFILE_TOKEN
./upload.sh backup.tar.gz
```

Find your token at: **GoFile.io → Account → API Token**. Treat it like a password — anyone with it can upload, and potentially manage, content in your account.

> **Note on GoFile's API docs:** publicly available documentation is inconsistent about whether the token should be sent as a form field or an `Authorization: Bearer` header. This script sends it both ways so it works regardless of which one GoFile's current backend actually reads. If your token is rejected, the script will now show GoFile's own error message rather than a generic parse failure.

### Examples

**Upload a custom ROM:**
```
./upload.sh lineage-20-pixel6-4.2GB.zip
```

**Upload a compressed archive to your account:**
```
./upload.sh -t YOUR_TOKEN backup.tar.gz
```

**Upload a PDF document:**
```
./upload.sh presentation.pdf
```

**Upload a video file:**
```
./upload.sh recording.mp4
```

## Output Example

```
File: lineage-20-pixel6-4.2GB.zip
Size: 4.2G
Account: guest (no token — file will be shorter-lived; pass -t/--token to upload to your account)

Fetching best GoFile server...
Using GoFile server: store3

Uploading file 'lineage-20-pixel6-4.2GB.zip' to GoFile...
This is a large file - upload may take 5-15+ minutes...

######################################################################## 100.0%

✓ File uploaded successfully!
Download Link: https://gofile.io/d/abc123
```

## Upload Time Estimates

The script provides intelligent time estimates based on file size:

- **< 500MB**: Quick upload (seconds to minutes)
- **500MB - 1GB**: A few minutes
- **1GB - 3GB**: 10-30 minutes
- **> 3GB**: 15-60+ minutes (depending on connection speed)

## Error Handling

The script includes comprehensive error handling for:

- ❌ Missing or unreadable files
- ❌ Missing dependencies (curl, jq, stat)
- ❌ GoFile API connection failures (with automatic retry)
- ❌ GoFile API error responses (e.g. an invalid token), surfaced with GoFile's own error message
- ❌ Server selection issues
- ❌ Upload failures
- ❌ Invalid API responses

All errors provide detailed messages to help troubleshoot issues. Temporary files are always cleaned up, even on Ctrl-C or an unexpected crash.

## Troubleshooting

### "Command not found: curl", "jq", or "stat"

Install the missing dependency using your package manager (see Requirements section).

### "Failed to connect to GoFile API"

- Check your internet connection
- Verify GoFile.io is accessible from your network
- The script already retries automatically 3 times on this step — if it still fails, try again after a few minutes

### "GoFile API error while ..."

- This means GoFile's API responded successfully but reported an error (for example, an invalid or expired token). The message shown is GoFile's own error text — check it for the specific cause.

### "File upload failed"

- Ensure the file is not corrupted
- Check if the file size exceeds GoFile's limits
- Verify you have sufficient internet bandwidth
- If using `-t`/`--token`, the token may have been rejected — try without it to confirm

### Upload is very slow

- Large files naturally take longer
- Check your upload speed:
```
sudo apt install speedtest-cli
speedtest-cli
```
- Consider uploading during off-peak hours

## Technical Details

### How It Works

1. Parses arguments (file path, optional token)
2. Validates file existence and readability
3. Checks for required dependencies
4. Queries GoFile API for the best server
5. Uploads file with progress tracking, optionally authenticated with your token
6. Extracts and displays the download link, or GoFile's error message on failure

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

### Credits:

- <https://gofile.io> - For the Amazing Website to upload Unlimited files with Unlimited filesize to fast servers, for free!
- [Sushrut1101](https://github.com/Sushrut1101) - To make the Script

---

**Note:** GoFile.io may have file size limits and retention policies. Check their website for current limitations. GoFile's API is also documented inconsistently across sources at time of writing — if an endpoint or auth method appears to have changed, please open an issue.
