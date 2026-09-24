#!/bin/bash
#
# Register-StartupUpdateCheck.sh
# Installs the launchd LaunchAgent for automatic background updates
#
# Usage: ./Register-StartupUpdateCheck.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENGINE_SCRIPT="$SCRIPT_DIR/StartupUpdateCheck.sh"
readonly PLIST_SOURCE="$SCRIPT_DIR/launchd/com.codex.backgroundupdatecheck.plist"
readonly LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
readonly PLIST_DEST="$LAUNCH_AGENTS_DIR/com.codex.backgroundupdatecheck.plist"
readonly SERVICE_LABEL="com.codex.backgroundupdatecheck"
readonly WORK_DIR="$HOME/.local/share/codex-background-update"

main() {
    echo "Universal Silent macOS Update Automator - Installation"
    echo "======================================================"
    echo

    # Verify macOS
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "ERROR: This script only runs on macOS"
        exit 1
    fi

    # Verify engine script exists
    if [[ ! -f "$ENGINE_SCRIPT" ]]; then
        echo "ERROR: Engine script not found: $ENGINE_SCRIPT"
        exit 1
    fi

    # Verify plist exists
    if [[ ! -f "$PLIST_SOURCE" ]]; then
        echo "ERROR: LaunchAgent plist not found: $PLIST_SOURCE"
        exit 1
    fi

    # Make engine script executable
    chmod +x "$ENGINE_SCRIPT"
    echo "✓ Made engine script executable"

    # Create working directory and copy engine script
    mkdir -p "$WORK_DIR"
    cp "$ENGINE_SCRIPT" "$WORK_DIR/StartupUpdateCheck.sh"
    chmod +x "$WORK_DIR/StartupUpdateCheck.sh"
    echo "✓ Installed engine script to $WORK_DIR"

    # Create LaunchAgents directory if needed
    mkdir -p "$LAUNCH_AGENTS_DIR"

    # Copy plist
    cp "$PLIST_SOURCE" "$PLIST_DEST"
    echo "✓ Installed LaunchAgent plist to $PLIST_DEST"

    # Unload existing if present
    if launchctl list | grep -q "$SERVICE_LABEL"; then
        launchctl unload "$PLIST_DEST" 2>/dev/null || true
        echo "✓ Unloaded existing LaunchAgent"
    fi

    # Load the LaunchAgent
    if launchctl load "$PLIST_DEST"; then
        echo "✓ Loaded LaunchAgent: $SERVICE_LABEL"
    else
        echo "ERROR: Failed to load LaunchAgent"
        exit 1
    fi

    # Verify it's loaded
    if launchctl list | grep -q "$SERVICE_LABEL"; then
        echo "✓ LaunchAgent verified as loaded"
    else
        echo "WARNING: LaunchAgent may not be fully loaded"
    fi

    echo
    echo "Installation complete!"
    echo
    echo "The updater will now run automatically:"
    echo "  • Every 6 hours (configurable in plist)"
    echo "  • Only when network is available"
    echo "  • Silently in the background"
    echo
    echo "Manual commands:"
    echo "  Test run (check only):     $ENGINE_SCRIPT"
    echo "  Test run (install):        $ENGINE_SCRIPT --require-network --install-updates"
    echo "  Dry run:                   $ENGINE_SCRIPT --dry-run"
    echo "  Uninstall:                 $SCRIPT_DIR/Unregister-StartupUpdateCheck.sh"
    echo
    echo "View LaunchAgent status:"
    echo "  launchctl list | grep $SERVICE_LABEL"
    echo
}

main "$@"