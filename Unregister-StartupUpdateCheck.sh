#!/bin/bash
#
# Unregister-StartupUpdateCheck.sh
# Removes the launchd LaunchAgent
#
# Usage: ./Unregister-StartupUpdateCheck.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
readonly PLIST_DEST="$LAUNCH_AGENTS_DIR/com.codex.backgroundupdatecheck.plist"
readonly SERVICE_LABEL="com.codex.backgroundupdatecheck"
readonly WORK_DIR="$HOME/.local/share/codex-background-update"

main() {
    echo "Universal Silent macOS Update Automator - Uninstallation"
    echo "========================================================"
    echo

    # Verify macOS
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "ERROR: This script only runs on macOS"
        exit 1
    fi

    # Unload LaunchAgent if loaded
    if launchctl list | grep -q "$SERVICE_LABEL"; then
        echo "Unloading LaunchAgent..."
        launchctl unload "$PLIST_DEST" 2>/dev/null || true
        echo "✓ LaunchAgent unloaded"
    else
        echo "LaunchAgent not currently loaded"
    fi

    # Remove plist
    if [[ -f "$PLIST_DEST" ]]; then
        rm -f "$PLIST_DEST"
        echo "✓ Removed LaunchAgent plist"
    else
        echo "LaunchAgent plist not found"
    fi

    # Clean up any stale lock
    rmdir "/tmp/com.codex.backgroundupdatecheck.lock" 2>/dev/null || true

    # Remove working directory
    if [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
        echo "✓ Removed working directory: $WORK_DIR"
    fi

    echo
    echo "Uninstallation complete!"
    echo "The background update automation has been removed."
}

main "$@"