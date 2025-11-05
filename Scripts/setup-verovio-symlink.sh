#!/bin/bash

# Setup script to create a symlink to Verovio data folder
# Run this once after cloning the repo or when Verovio package is first downloaded

set -e

echo "🔗 Setting up Verovio data symlink..."

# Find the Verovio data folder in DerivedData
VEROVIO_DATA=$(find ~/Library/Developer/Xcode/DerivedData -path "*/SourcePackages/checkouts/verovio/data" -type d 2>/dev/null | head -1)

if [ -z "$VEROVIO_DATA" ]; then
    echo "❌ error: Verovio data folder not found in DerivedData."
    echo ""
    echo "Please open the project in Xcode first and let Swift Package Manager"
    echo "download the Verovio package, then run this script again."
    exit 1
fi

echo "   Found Verovio data at: $VEROVIO_DATA"

# Get the script's directory and go to project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

SYMLINK_PATH="$PROJECT_ROOT/MusicSheetsCopilot/Resources/verovio-data"

# Remove existing symlink/folder if it exists
if [ -e "$SYMLINK_PATH" ]; then
    echo "   Removing existing symlink/folder..."
    rm -rf "$SYMLINK_PATH"
fi

# Create the symlink
echo "   Creating symlink..."
ln -s "$VEROVIO_DATA" "$SYMLINK_PATH"

if [ -L "$SYMLINK_PATH" ]; then
    echo "✅ Symlink created successfully!"
    echo "   $SYMLINK_PATH → $VEROVIO_DATA"
    echo ""
    echo "Now you can build the project in Xcode."
else
    echo "❌ error: Failed to create symlink"
    exit 1
fi
