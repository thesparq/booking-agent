#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

mkdir -p "$BUILD_DIR"

NEEDS_BUILD=false
if [[ ! -f "$BUILD_DIR/booking_core.wasm" || "${1:-}" == "--force" ]]; then
    NEEDS_BUILD=true
else
    for f in "$SCRIPT_DIR/src"/*.roc; do
        if [[ "$f" -nt "$BUILD_DIR/booking_core.wasm" ]]; then
            NEEDS_BUILD=true
            break
        fi
    done
fi

if [[ "$NEEDS_BUILD" == "true" ]]; then
    echo "==> Building Salon Booking Agent with roc build (using GitHub release platform)..."
    roc build --target=wasm32 "$SCRIPT_DIR/src/main.roc" --output="$BUILD_DIR/booking_core.wasm" || {
        STATUS=$?
        if [[ $STATUS -ne 2 || ! -f "$BUILD_DIR/booking_core.wasm" ]]; then
            echo "Error: roc build failed with status $STATUS" >&2
            exit $STATUS
        fi
    }
else
    echo "==> Source files unchanged. Using cached $BUILD_DIR/booking_core.wasm (pass --force to rebuild)"
fi

echo "==> Componentizing WASM module into Golem Component Model..."
wasm-tools component new "$BUILD_DIR/booking_core.wasm" -o "$BUILD_DIR/booking_agent.wasm"

echo "==> Validating Component Model compatibility..."
wasm-tools validate "$BUILD_DIR/booking_agent.wasm"

echo "============================================================"
echo " App build finished successfully using GitHub release platform!"
echo " Component: $BUILD_DIR/booking_agent.wasm"
echo " Size:      $(du -h "$BUILD_DIR/booking_agent.wasm" | cut -f1)"
echo "============================================================"
