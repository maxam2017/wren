#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Temporary directory for download
TMP_DIR="/tmp/wren-install"
INSTALL_DIR="$HOME/.wren"

echo "📦 Installing Wren..."

# Create temporary directory
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Download repository
if ! git clone --depth 1 https://github.com/maxam2017/wren.git "$TMP_DIR" 2>/dev/null; then
    echo -e "${RED}❌ Failed to download Wren${NC}"
    exit 1
fi

# run main.sh install
"$TMP_DIR/main.sh" install -f
