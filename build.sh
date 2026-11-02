#!/usr/bin/env bash
# Exports the game into build/.
#   ./build.sh            -> macOS + Windows
#   ./build.sh macos      -> only macOS (.dmg)
#   ./build.sh windows    -> only Windows (.exe + .zip)
# Godot path can be overridden: GODOT=/path/to/Godot ./build.sh
set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${GODOT:-}" ]]; then
    for candidate in \
        "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
        "/Applications/Godot.app/Contents/MacOS/Godot" \
        "$(command -v godot 2>/dev/null || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            GODOT="$candidate"
            break
        fi
    done
fi
if [[ -z "${GODOT:-}" ]]; then
    echo "Godot not found. Run: GODOT=/path/to/Godot ./build.sh" >&2
    exit 1
fi

target="${1:-all}"

export_macos() {
    echo "==> macOS"
    mkdir -p build/macos
    rm -f build/macos/project-x.dmg
    "$GODOT" --headless --path . --export-release "macOS" build/macos/project-x.dmg
    echo "    build/macos/project-x.dmg"
}

export_windows() {
    echo "==> Windows"
    mkdir -p build/windows
    rm -f build/windows/project-x.exe build/windows/project-x-windows.zip
    "$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/project-x.exe
    (cd build/windows && zip -q project-x-windows.zip project-x.exe)
    echo "    build/windows/project-x.exe"
    echo "    build/windows/project-x-windows.zip"
}

case "$target" in
    macos)   export_macos ;;
    windows) export_windows ;;
    all)     export_macos; export_windows ;;
    *)       echo "Usage: ./build.sh [macos|windows|all]" >&2; exit 1 ;;
esac

echo "Done."
