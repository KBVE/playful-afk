#!/bin/bash
set -e

# Godo GDExtension Sync Script
# Builds the extension for multiple platforms and copies to /afk/addons/godo/
# This makes the extension self-contained as a Godot plugin (no ../ paths needed)

# Add cargo to PATH if it exists
if [ -d "$HOME/.cargo/bin" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Source Rust environment if available
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

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

# Pre-flight: terminate running Godot instances to avoid locking dylibs
echo "Pre-flight: checking for running Godot instances..."
if pkill -9 Godot >/dev/null 2>&1; then
    echo "  ✓ Terminated existing Godot processes"
else
    echo "  ℹ No running Godot processes found (or unable to terminate)"
fi
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
    echo "  → Building WASM debug with nightly toolchain (size-optimized)..."
    CARGO_PROFILE_DEV_DEBUG=false \
    CARGO_PROFILE_DEV_OPT_LEVEL=s \
    CARGO_PROFILE_DEV_STRIP=debuginfo \
    CARGO_PROFILE_DEV_PANIC=abort \
    CARGO_PROFILE_DEV_LTO=thin \
    CARGO_PROFILE_DEV_CODEGEN_UNITS=1 \
    CARGO_PROFILE_DEV_INCREMENTAL=false \
        cargo +nightly build -Zbuild-std=std,panic_abort --target wasm32-unknown-emscripten
    echo "  ✓ WASM debug build complete"

    echo "  → Building WASM release with nightly toolchain..."
    cargo +nightly build -Zbuild-std=std,panic_abort --target wasm32-unknown-emscripten --release
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
    # Remove quarantine and re-sign for macOS
    xattr -dr com.apple.quarantine "$PLUGIN_DIR/bin/debug/libgodo.dylib" 2>/dev/null || true
    codesign --force --sign - "$PLUGIN_DIR/bin/debug/libgodo.dylib" 2>/dev/null || true
    echo "  ✓ Signed: libgodo.dylib (debug)"
else
    echo "  ✗ Missing: libgodo.dylib (debug)"
fi

# macOS Release
if [ -f "$TARGET_DIR/release/libgodo.dylib" ]; then
    cp "$TARGET_DIR/release/libgodo.dylib" "$PLUGIN_DIR/bin/release/"
    echo "  ✓ Copied: libgodo.dylib (release)"
    # Remove quarantine and re-sign for macOS
    xattr -dr com.apple.quarantine "$PLUGIN_DIR/bin/release/libgodo.dylib" 2>/dev/null || true
    codesign --force --sign - "$PLUGIN_DIR/bin/release/libgodo.dylib" 2>/dev/null || true
    echo "  ✓ Signed: libgodo.dylib (release)"
else
    echo "  ✗ Missing: libgodo.dylib (release)"
fi

# WASM (Note: emscripten builds use godo.wasm, not libgodo.wasm)
WASM_DEBUG_PATH="$TARGET_DIR/wasm32-unknown-emscripten/dev-wasm/godo.wasm"
if [ ! -f "$WASM_DEBUG_PATH" ]; then
    WASM_DEBUG_PATH="$TARGET_DIR/wasm32-unknown-emscripten/debug/godo.wasm"
fi
if [ -f "$WASM_DEBUG_PATH" ]; then
    cp "$WASM_DEBUG_PATH" "$PLUGIN_DIR/bin/debug/"
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

LOG_FILE="$SCRIPT_DIR/logs.txt"
LOG_ARCHIVE="$SCRIPT_DIR/logs_archive.txt"

if [ -f "$LOG_ARCHIVE" ]; then
    LINE_COUNT=$(wc -l < "$LOG_ARCHIVE")
    if [ "$LINE_COUNT" -gt 100000 ]; then
        echo "Logs archive exceeds 100,000 lines; resetting..."
        : > "$LOG_ARCHIVE"
    fi
fi

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    echo "Archiving previous Godot logs..."
    {
        echo "----- Archived on $(date '+%Y-%m-%d %H:%M:%S') -----"
        cat "$LOG_FILE"
        echo ""
    } >>"$LOG_ARCHIVE"
fi
: > "$LOG_FILE"

echo "Attempting to restart Godot editor with AFK project..."
if command -v godot >/dev/null 2>&1; then
    echo "  → Godot output will be appended to: $LOG_FILE"
    (cd "$AFK_DIR" && nohup godot --editor --path "$AFK_DIR" >>"$LOG_FILE" 2>&1 &)
    echo "✓ Godot editor launched in background (project: $AFK_DIR)"
else
    echo "⚠ 'godot' CLI not found in PATH; please start Godot manually."
fi
