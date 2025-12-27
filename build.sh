#!/bin/bash
set -e

echo "=== Building Roc WebSocket Chat Server (Zig Platform) ==="

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Step 1: Build the Zig host library
echo ""
echo "1. Building Zig host library..."
if command -v zig &> /dev/null; then
    zig build native
    echo "   ✓ Host library built"
else
    echo "   ⚠ Zig not found - skipping host library build"
    echo "   Install Zig from https://ziglang.org/download/ and run:"
    echo "   zig build native"
fi

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
    # Use --linker=legacy flag for Linux when using json package (issue #3609)
    roc build app/main.roc --linker=legacy
    echo "   ✓ Roc application built"
else
    echo "   ⚠ Roc not found - skipping application build"
    echo "   Install Roc from https://www.roc-lang.org/"
fi

echo ""
echo "=== Build Complete ==="
echo ""
echo "To run the chat server:"
echo "  ./app/main"
echo ""
echo "Then open your browser to:"
echo "  http://localhost:8080"
