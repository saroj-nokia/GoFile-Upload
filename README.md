# GoFile Upload Script

A robust bash script to upload files to GoFile.io with automatic server selection and download link generation. Optimized for large files (1-4 GB) with smart progress indicators and comprehensive error handling.

## Features

- ✅ **Smart File Detection** - Automatically detects file size and shows appropriate upload time estimates
- ✅ **Memory Optimized** - Uses temporary files to handle large uploads without consuming excessive RAM
- ✅ **Automatic Server Selection** - Queries GoFile API to find the best available server
- ✅ **Progress Tracking** - Shows upload progress with visual progress bar
- ✅ **Robust Error Handling** - Comprehensive checks with detailed error messages
- ✅ **Automatic Cleanup** - Removes temporary files even if script crashes
- ✅ **Cross-Platform** - Works on Linux and macOS

## Requirements

- `bash` (4.0+)
- `curl` - For making HTTP requests
- `jq` - For parsing JSON responses

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

### Method 1: Download the Script
```bash
# Download the script
curl -o upload.sh https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh

# Make it executable
chmod +x upload.sh
```

### Method 2: Quick Use (Without Downloading)
You can run the script directly without downloading:

```bash
curl -s https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh | bash -s -- /path/to/your/file.zip
```

### Method 3: Install Globally
```bash
# Download to /usr/local/bin
sudo curl -o /usr/local/bin/gofile-upload https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh

# Make it executable
sudo chmod +x /usr/local/bin/gofile-upload

# Now you can use it from anywhere
gofile-upload /path/to/file.zip
```

## Usage

### Basic Usage
```bash
./upload.sh /path/to/your/file.zip
```

### Examples

**Upload a custom ROM:**
```bash
./upload.sh lineage-20-pixel6-4.2GB.zip
```

**Upload a compressed archive:**
```bash
./upload.sh backup.tar.gz
```

**Upload a PDF document:**
```bash
./upload.sh presentation.pdf
```

**Upload a video file:**
```bash
./upload.sh recording.mp4
```

## Output Example

```
File: lineage-20-pixel6-4.2GB.zip
Size: 4.2G

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
- **> 1GB**: 5-15+ minutes (depending on connection speed)

## Error Handling

The script includes comprehensive error handling for:

- ❌ Missing or unreadable files
- ❌ Missing dependencies (curl, jq)
- ❌ GoFile API connection failures
- ❌ Server selection issues
- ❌ Upload failures
- ❌ Invalid API responses

All errors provide detailed messages to help troubleshoot issues.

## Troubleshooting

### "Command not found: curl" or "Command not found: jq"
Install the missing dependencies using your package manager (see Requirements section).

### "Failed to connect to GoFile API"
- Check your internet connection
- Verify GoFile.io is accessible from your network
- Try again after a few minutes

### "File upload failed"
- Ensure the file is not corrupted
- Check if the file size exceeds GoFile's limits
- Verify you have sufficient internet bandwidth

### Upload is very slow
- Large files naturally take longer
- Check your upload speed:
```bash
# Install speedtest-cli if needed
sudo apt install speedtest-cli

# Test your upload speed
speedtest-cli
```
- Consider uploading during off-peak hours

## Technical Details

### How It Works
1. Validates file existence and readability
2. Checks for required dependencies
3. Queries GoFile API for the best server
4. Uploads file with progress tracking
5. Extracts and displays the download link

### Memory Usage
- Small files (< 500MB): Minimal memory usage
- Large files (1-4GB): Uses temporary files to avoid high RAM consumption
- Peak memory: ~50MB regardless of file size

### Security
- No API keys required
- Files are uploaded directly to GoFile's servers
- Temporary files are automatically cleaned up
- No data is stored locally after upload

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
- https://gofile.io - For the Amazing Website to upload Unlimited files with Unlimited filesize to fast servers, for free!
- [Sushrut1101](https://github.com/Sushrut1101) - To make the Script

---

**Note:** GoFile.io may have file size limits and retention policies. Check their website for current limitations.
