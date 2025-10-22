#!/bin/bash
set -e

# Godo GDExtension Sync Script
# Builds the extension for multiple platforms and copies to /afk/addons/godo/
# This makes the extension self-contained as a Godot plugin (no ../ paths needed)

# Source Rust environment if available
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AFK_DIR="$(cd "$SCRIPT_DIR/../afk" && pwd)"
PLUGIN_DIR="$AFK_DIR/addons/godo"
TARGET_DIR="$SCRIPT_DIR/target"

echo "======================================"
echo "Godo GDExtension Build & Sync"
echo "======================================"
echo "Rust dir:   $SCRIPT_DIR"
echo "AFK dir:    $AFK_DIR"
echo "Plugin dir: $PLUGIN_DIR"
echo ""

# Step 1: Create plugin directory structure
echo "[1/4] Creating plugin directories..."
mkdir -p "$PLUGIN_DIR/bin/debug"
mkdir -p "$PLUGIN_DIR/bin/release"
echo "✓ Created: $PLUGIN_DIR/bin/debug"
echo "✓ Created: $PLUGIN_DIR/bin/release"
echo ""

# Step 2: Build for macOS (debug and release)
echo "[2/4] Building for macOS..."
echo "  → Building debug..."
cargo build
echo "  ✓ macOS debug build complete"

echo "  → Building release..."
cargo build --release
echo "  ✓ macOS release build complete"
echo ""

# Step 3: Build for WASM (if emsdk is available)
echo "[3/4] Building for WASM..."
if command -v emcc &> /dev/null; then
    echo "  → Building WASM debug with nightly toolchain..."
    cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten
    echo "  ✓ WASM debug build complete"

    echo "  → Building WASM release with nightly toolchain..."
    cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten --release
    echo "  ✓ WASM release build complete"
else
    echo "  ⚠ WASM build skipped (emsdk not found)"
    echo "  → To enable WASM builds, install emsdk first"
fi
echo ""

# Step 4: Copy binaries to plugin folder
echo "[4/4] Copying binaries to plugin..."

# macOS Debug
if [ -f "$TARGET_DIR/debug/libgodo.dylib" ]; then
    cp "$TARGET_DIR/debug/libgodo.dylib" "$PLUGIN_DIR/bin/debug/"
    echo "  ✓ Copied: libgodo.dylib (debug)"
else
    echo "  ✗ Missing: libgodo.dylib (debug)"
fi

# macOS Release
if [ -f "$TARGET_DIR/release/libgodo.dylib" ]; then
    cp "$TARGET_DIR/release/libgodo.dylib" "$PLUGIN_DIR/bin/release/"
    echo "  ✓ Copied: libgodo.dylib (release)"
else
    echo "  ✗ Missing: libgodo.dylib (release)"
fi

# WASM (Note: emscripten builds use godo.wasm, not libgodo.wasm)
if [ -f "$TARGET_DIR/wasm32-unknown-emscripten/debug/godo.wasm" ]; then
    cp "$TARGET_DIR/wasm32-unknown-emscripten/debug/godo.wasm" "$PLUGIN_DIR/bin/debug/"
    echo "  ✓ Copied: godo.wasm (debug)"
fi

if [ -f "$TARGET_DIR/wasm32-unknown-emscripten/release/godo.wasm" ]; then
    cp "$TARGET_DIR/wasm32-unknown-emscripten/release/godo.wasm" "$PLUGIN_DIR/bin/release/"
    echo "  ✓ Copied: godo.wasm (release)"
fi

# Linux (if built)
if [ -f "$TARGET_DIR/debug/libgodo.so" ]; then
    cp "$TARGET_DIR/debug/libgodo.so" "$PLUGIN_DIR/bin/debug/"
    echo "  ✓ Copied: libgodo.so (debug)"
fi

if [ -f "$TARGET_DIR/release/libgodo.so" ]; then
    cp "$TARGET_DIR/release/libgodo.so" "$PLUGIN_DIR/bin/release/"
    echo "  ✓ Copied: libgodo.so (release)"
fi

# Windows (if built)
if [ -f "$TARGET_DIR/debug/godo.dll" ]; then
    cp "$TARGET_DIR/debug/godo.dll" "$PLUGIN_DIR/bin/debug/"
    echo "  ✓ Copied: godo.dll (debug)"
fi

if [ -f "$TARGET_DIR/release/godo.dll" ]; then
    cp "$TARGET_DIR/release/godo.dll" "$PLUGIN_DIR/bin/release/"
    echo "  ✓ Copied: godo.dll (release)"
fi

echo ""
echo "======================================"
echo "✓ Sync complete!"
echo "======================================"
echo "Plugin location: $PLUGIN_DIR"
echo ""
echo "Next steps:"
echo "1. Update godo.gdextension to use plugin paths"
echo "2. Move godo.gdextension to: $PLUGIN_DIR/"
echo "3. Restart Godot to load the plugin"
