#!/usr/bin/env bash
#MISE description="Release a new version of the CLI"
#USAGE arg "<product>" help="Product name (e.g., egg)"
#USAGE arg "<version>" help="Version to release (e.g., 1.0.0)"

set -eo pipefail

echo "Releasing $usage_product $usage_version"

# Validate version format (semver)
if ! [[ "$usage_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: Invalid version format. Expected semver (e.g., 1.0.0, 1.0.0-beta.1)"
    exit 1
fi

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is required but not installed."
    echo "Install it with: brew install gh"
    exit 1
fi

# Check gh authentication
if ! gh auth status &> /dev/null; then
    echo "Error: GitHub CLI is not authenticated. Run: gh auth login"
    exit 1
fi

# Build for both architectures
echo "Building for x86_64..."
swift build -c release --triple x86_64-apple-macosx

echo "Building for arm64..."
swift build -c release --triple arm64-apple-macosx

# Create universal binary with lipo
echo "Creating universal binary..."
lipo -create -output .build/"$usage_product" \
    .build/{arm64,x86_64}-apple-macosx/release/"$usage_product"

# Verify universal binary
echo "Verifying universal binary..."
lipo -info .build/"$usage_product"

# Create temporary directory for zip and ensure cleanup
temp_dir=$(mktemp -d)
zip_path="$temp_dir/${usage_product}-${usage_version}-macos.zip"
trap 'rm -rf "$temp_dir"' EXIT

# Compress the binary
echo "Creating ZIP archive..."
/usr/bin/ditto -c -k .build/"$usage_product" "$zip_path"

# Calculate SHA256
sha256=$(shasum -a 256 "$zip_path" | awk '{print $1}')
echo "SHA256: $sha256"

# Get repository info
repo_info=$(gh repo view --json owner,name -q '.owner.login + "/" + .name')

# Create release notes
release_notes="## Installation

### Using mise with UBI (recommended)

\`\`\`bash
mise use -g ubi:${repo_info}@${usage_version}
\`\`\`

### Manual installation

1. Download the ZIP file from the assets below
2. Extract and move the binary to your PATH:
   \`\`\`bash
   unzip ${usage_product}-${usage_version}-macos.zip
   sudo mv ${usage_product} /usr/local/bin/
   \`\`\`

## Checksums

- **SHA256**: \`${sha256}\`
"

# Create GitHub release
echo "Creating GitHub release $usage_version..."
gh release create "$usage_version" \
    --title "$usage_version" \
    --notes "$release_notes" \
    "$zip_path"

echo "Release $usage_version created and uploaded successfully"
echo "Release URL: $(gh release view "$usage_version" --json url -q '.url')"
