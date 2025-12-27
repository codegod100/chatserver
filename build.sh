#!/bin/bash
set -e

echo "=== Building Roc WebSocket Chat Server ==="

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Step 1: Build the Zig host library
echo ""
echo "1. Building Zig host library..."
zig build x64musl
echo "   ✓ Host library built"

# Step 2: Build Elm frontend (if elm is available)
echo ""
echo "2. Building Elm frontend..."
if command -v elm &> /dev/null; then
    cd frontend
    elm make src/Main.elm --optimize --output=../static/elm.js
    cd ..
    echo "   ✓ Elm frontend built"
else
    echo "   ⚠ Elm not found - skipping frontend build"
    echo "   Install Elm from https://elm-lang.org/ and run:"
    echo "   cd frontend && elm make src/Main.elm --optimize --output=../static/elm.js"
fi

# Step 3: Build Roc application
echo ""
echo "3. Building Roc application..."
if command -v roc &> /dev/null; then
    ../roc/zig-out/bin/roc app/main.roc
    echo "   ✓ Roc application built"
else
    echo "   ⚠ Roc not found - skipping application build"
    echo "   Install Roc from https://www.roc-lang.org/"
fi

echo ""
echo "=== Build Complete ==="
echo ""
echo "To run the chat server:"
echo "  ./chatserver"
echo ""
echo "Then open your browser to:"
echo "  http://localhost:8080"
