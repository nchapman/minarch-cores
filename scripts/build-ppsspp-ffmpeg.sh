#!/bin/bash
# Build PPSSPP's custom ffmpeg for a given architecture
# Called automatically by core_builder.rb for ppsspp
# Usage: ./build-ppsspp-ffmpeg.sh <arch> <ppsspp-core-dir>

set -e

ARCH=$1
PPSSPP_DIR=$2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FFMPEG_REPO="$PROJECT_ROOT/external/ppsspp-ffmpeg"

if [ -z "$ARCH" ] || [ -z "$PPSSPP_DIR" ]; then
    echo "Usage: $0 <arch> <ppsspp-core-dir>"
    exit 1
fi

# Clone ppsspp-ffmpeg if not exists
if [ ! -d "$FFMPEG_REPO" ]; then
    echo "Cloning ppsspp-ffmpeg..."
    mkdir -p "$(dirname "$FFMPEG_REPO")"
    git clone --depth 1 https://github.com/hrydgard/ppsspp-ffmpeg.git "$FFMPEG_REPO" > /dev/null 2>&1
fi

# Map architecture to build script
case "$ARCH" in
    arm|armv7)
        BUILD_SCRIPT="linux_arm.sh"
        OUTPUT_DIR="linux/armv7"
        ;;
    arm64|aarch64)
        BUILD_SCRIPT="linux_arm64.sh"
        OUTPUT_DIR="linux/aarch64"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Check if already built (ffmpeg build is slow, cache it)
if [ -f "$FFMPEG_REPO/$OUTPUT_DIR/lib/libavcodec.a" ]; then
    # Already built, just copy
    mkdir -p "$PPSSPP_DIR/ffmpeg/linux"
    cp -r "$FFMPEG_REPO/$OUTPUT_DIR" "$PPSSPP_DIR/ffmpeg/linux/"
    exit 0
fi

# Build ffmpeg from source (2-3 minutes)
echo "Building FFmpeg for $ARCH (this takes 2-3 minutes, cached after first build)..."
cd "$FFMPEG_REPO"
./$BUILD_SCRIPT > /dev/null 2>&1

# Copy to ppsspp source
mkdir -p "$PPSSPP_DIR/ffmpeg/linux"
cp -r "$FFMPEG_REPO/$OUTPUT_DIR" "$PPSSPP_DIR/ffmpeg/linux/"

echo "FFmpeg built successfully for $ARCH"
