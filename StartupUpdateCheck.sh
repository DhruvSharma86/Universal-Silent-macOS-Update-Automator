#!/bin/bash
#
# Universal Silent macOS Update Automator
# Updates macOS, App Store apps, Homebrew, and supported third-party applications
# silently in the background when network is available.
#
# Usage: ./StartupUpdateCheck.sh [--require-network] [--install-updates] [--dry-run]

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
readonly LOCK_DIR="/tmp/com.codex.backgroundupdatecheck.lock"
readonly LOCK_FD=200
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="${HOME}/.local/state/codex-background-update"
readonly LAST_RUN_FILE="${STATE_DIR}/last-run-date"

# Timeouts (seconds)
readonly TIMEOUT_MACOS_UPDATE=1800     # 30 min
readonly TIMEOUT_APP_STORE=900         # 15 min
readonly TIMEOUT_HOMEBREW=900          # 15 min
readonly TIMEOUT_STEAM=900             # 15 min
readonly TIMEOUT_EPIC=900              # 15 min
readonly TIMEOUT_THIRD_PARTY=900       # 15 min

# ─── Flags ───────────────────────────────────────────────────────────────────
REQUIRE_NETWORK=false
INSTALL_UPDATES=false
DRY_RUN=false

# ─── Helpers ──────────────────────────────────────────────────────────────────

log() {
    # In production: silent. For debugging: uncomment next line
    # echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
    :
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

die() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --require-network) REQUIRE_NETWORK=true ;;
            --install-updates) INSTALL_UPDATES=true ;;
            --dry-run) DRY_RUN=true ;;
            -h|--help)
                cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]
Options:
  --require-network    Only run if network is available
  --install-updates    Actually install updates (not just check)
  --dry-run            Show what would be done without installing
  -h, --help           Show this help
EOF
                exit 0
                ;;
            *) die "Unknown option: $1" ;;
        esac
        shift
    done
}

# Lock mechanism using mkdir (portable, works on all macOS versions)
acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        # Lock acquired
        trap 'release_lock' EXIT INT TERM
        return 0
    else
        # Lock exists, check if stale (older than 2 hours)
        if [[ -d "$LOCK_DIR" ]]; then
            local lock_age
            lock_age=$(($(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)))
            if [[ $lock_age -gt 7200 ]]; then
                warn "Stale lock detected (age ${lock_age}s), removing"
                rmdir "$LOCK_DIR" 2>/dev/null && acquire_lock && return 0
            fi
        fi
        return 1
    fi
}

release_lock() {
    rmdir "$LOCK_DIR" 2>/dev/null || true
    trap - EXIT INT TERM
}

# Network check
check_network() {
    if ! $REQUIRE_NETWORK; then
        return 0
    fi

    # Try multiple connectivity checks
    if ping -c 1 -W 2000 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi

    if ping -c 1 -W 2000 1.1.1.1 >/dev/null 2>&1; then
        return 0
    fi

    # Check default gateway
    local gateway
    gateway=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
    if [[ -n "$gateway" ]] && ping -c 1 -W 2000 "$gateway" >/dev/null 2>&1; then
        return 0
    fi

    log "Network not available, exiting"
    return 1
}

# Timeout wrapper using timeout command (macOS 10.15+ has it) or perl fallback
run_with_timeout() {
    local timeout_seconds=$1
    shift
    local cmd=("$@")

    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_seconds" "${cmd[@]}"
        return $?
    else
        # Fallback using perl
        perl -e "alarm $timeout_seconds; exec @ARGV" "${cmd[@]}"
        return $?
    fi
}

# Check if already run today (prevents multiple runs per day)
check_daily_run() {
    mkdir -p "$STATE_DIR"
    local today
    today=$(date '+%Y-%m-%d')
    
    if [[ -f "$LAST_RUN_FILE" ]]; then
        local last_run
        last_run=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "")
        if [[ "$last_run" == "$today" ]]; then
            log "Already ran today ($today), skipping"
            return 1
        fi
    fi
    
    # Record today's run
    echo "$today" > "$LAST_RUN_FILE"
    return 0
}

# Process detection
is_process_running() {
    local process_name=$1
    pgrep -x "$process_name" >/dev/null 2>&1
}

# Find Homebrew
find_brew() {
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        echo "/opt/homebrew/bin/brew"
        return 0
    fi
    if [[ -x "/usr/local/bin/brew" ]]; then
        echo "/usr/local/bin/brew"
        return 0
    fi
    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi
    return 1
}

# Find mas (Mac App Store CLI)
find_mas() {
    local brew_path
    brew_path=$(find_brew) || return 1

    if [[ -x "$(dirname "$brew_path")/mas" ]]; then
        echo "$(dirname "$brew_path")/mas"
        return 0
    fi
    if command -v mas >/dev/null 2>&1; then
        command -v mas
        return 0
    fi
    return 1
}

# ─── Update Providers ────────────────────────────────────────────────────────

# macOS System Updates
provider_macos_update() {
    log "=== Provider: macOS System Update ==="

    if ! $INSTALL_UPDATES && ! $DRY_RUN; then
        log "Check-only mode, skipping macOS update"
        return 0
    fi

    if ! command -v softwareupdate >/dev/null 2>&1; then
        warn "softwareupdate not found"
        return 1
    fi

    if $DRY_RUN; then
        log "DRY-RUN: Would check for macOS updates"
        /usr/sbin/softwareupdate -l 2>/dev/null || true
        return 0
    fi

    # Check for available updates first
    local updates
    updates=$(/usr/sbin/softwareupdate -l 2>&1) || {
        warn "Failed to list macOS updates"
        return 1
    }

    if [[ "$updates" == *"No new software available"* ]]; then
        log "No macOS updates available"
        return 0
    fi

    log "Installing macOS updates..."
    # Use --no-scan to avoid rescanning, --agree-to-license for non-interactive
    # --restart is NOT used - we never force restart
    run_with_timeout "$TIMEOUT_MACOS_UPDATE" \
        /usr/sbin/softwareupdate -i -a --agree-to-license --no-scan 2>&1 || {
        warn "macOS update completed with warnings (may require restart)"
        return 0  # Don't fail the whole run
    }

    log "macOS updates installed"
    return 0
}

# Mac App Store Updates
provider_app_store() {
    log "=== Provider: Mac App Store ==="

    if ! $INSTALL_UPDATES && ! $DRY_RUN; then
        log "Check-only mode, skipping App Store"
        return 0
    fi

    local mas_path
    mas_path=$(find_mas) || {
        log "mas not installed, skipping App Store updates"
        return 0
    }

    if $DRY_RUN; then
        log "DRY-RUN: Would check App Store updates"
        "$mas_path" outdated 2>/dev/null || true
        return 0
    fi

    # mas requires authentication for many operations
    # Try to upgrade, but handle auth failures gracefully
    log "Checking App Store updates..."
    local outdated
    outdated=$("$mas_path" outdated 2>&1) || {
        warn "Failed to list App Store updates (may need authentication)"
        return 0
    }

    if [[ -z "$outdated" ]]; then
        log "No App Store updates available"
        return 0
    fi

    log "Installing App Store updates..."
    # mas upgrade may prompt for password - we can't handle that silently
    # Run with timeout and accept failure
    run_with_timeout "$TIMEOUT_APP_STORE" \
        "$mas_path" upgrade 2>&1 || {
        warn "App Store update completed with warnings (may require authentication)"
        return 0
    }

    log "App Store updates installed"
    return 0
}

# Homebrew Updates
provider_homebrew() {
    log "=== Provider: Homebrew ==="

    if ! $INSTALL_UPDATES && ! $DRY_RUN; then
        log "Check-only mode, skipping Homebrew"
        return 0
    fi

    local brew_path
    brew_path=$(find_brew) || {
        log "Homebrew not installed, skipping"
        return 0
    }

    # Check if another brew process is running
    if pgrep -f "^$brew_path" >/dev/null 2>&1; then
        log "Homebrew already running, skipping"
        return 0
    fi

    if $DRY_RUN; then
        log "DRY-RUN: Would run brew update && brew upgrade"
        "$brew_path" outdated 2>/dev/null || true
        "$brew_path" outdated --cask 2>/dev/null || true
        return 0
    fi

    log "Updating Homebrew..."
    run_with_timeout "$TIMEOUT_HOMEBREW" \
        "$brew_path" update 2>&1 || {
        warn "Homebrew update failed"
    }

    log "Upgrading Homebrew packages..."
    run_with_timeout "$TIMEOUT_HOMEBREW" \
        "$brew_path" upgrade 2>&1 || {
        warn "Homebrew upgrade completed with warnings"
    }

    log "Upgrading Homebrew casks..."
    run_with_timeout "$TIMEOUT_HOMEBREW" \
        "$brew_path" upgrade --cask 2>&1 || {
        warn "Homebrew cask upgrade completed with warnings"
    }

    # Cleanup (safe - only removes old versions)
    run_with_timeout 120 \
        "$brew_path" cleanup --prune=all 2>&1 || true

    log "Homebrew updates completed"
    return 0
}

# NVIDIA (detect and skip on Apple Silicon)
provider_nvidia() {
    log "=== Provider: NVIDIA ==="

    if ! $INSTALL_UPDATES && ! $DRY_RUN; then
        return 0
    fi

    # Check for NVIDIA GPU
    if ! system_profiler SPDisplaysDataType 2>/dev/null | grep -qi nvidia; then
        log "No NVIDIA GPU detected, skipping"
        return 0
    fi

    # On modern macOS (especially Apple Silicon), NVIDIA drivers are not supported
    local os_version
    os_version=$(sw_vers -productVersion)
    local major_version=${os_version%%.*}

    if [[ "$(uname -m)" == "arm64" ]] || [[ $major_version -ge 12 ]]; then
        log "NVIDIA drivers not supported on this macOS/architecture, skipping"
        return 0
    fi

    # Legacy Intel Mac with NVIDIA - check for NVIDIA driver manager
    if [[ -x "/Library/Application Support/NVIDIA/Drivers/NVIDIA Driver Manager.app/Contents/MacOS/NVIDIA Driver Manager" ]]; then
        if $DRY_RUN; then
            log "DRY-RUN: Would check NVIDIA driver updates"
            return 0
        fi
        # No reliable silent CLI for NVIDIA on macOS
        log "NVIDIA detected but no silent update mechanism available"
    fi

    return 0
}

# Steam
provider_steam() {
    log "=== Provider: Steam ==="

    if ! $INSTALL_UPDATES && ! $DRY_RUN; then
        return 0
    fi

    local steam_app="/Applications/Steam.app"
    if [[ ! -d "$steam_app" ]]; then
        log "Steam not installed, skipping"
        return 0
    fi

    # Check if Steam is already running
    if is_process_running "steam" || is_process_running "Steam"; then
        log "Steam already running, skipping launch"
        return 0
    fi

    if $DRY_RUN; then
        log "DRY-RUN: Would launch Steam for updates"
        return 0
    fi

    # On macOS, Steam doesn't have a documented -silent flag
    # Best effort: launch the app (it will check for updates on startup)
    log "Launching Steam for self/game updates..."
    run_with_timeout "$TIMEOUT_STEAM" \
        open -g -a "$steam_app" 2>&1 || {
        warn "Failed to launch Steam"
        return 0
    }

    log "Steam launched for updates"
    return 0
}

# Epic Games Launcher
provider_epic() {
    log "=== Provider: Epic Games ==="

    if ! $INSTALL_UPDATES && ! $DRY_RUN; then
        return 0
    fi

    local epic_app="/Applications/Epic Games Launcher.app"
    if [[ ! -d "$epic_app" ]]; then
        log "Epic Games Launcher not installed, skipping"
        return 0
    fi

    if is_process_running "EpicGamesLauncher"; then
        log "Epic Games Launcher already running, skipping"
        return 0
    fi

    if $DRY_RUN; then
        log "DRY-RUN: Would launch Epic Games Launcher"
        return 0
    fi

    # No documented silent launch flags on macOS
    log "Launching Epic Games Launcher for updates..."
    run_with_timeout "$TIMEOUT_EPIC" \
        open -g -a "$epic_app" 2>&1 || {
        warn "Failed to launch Epic Games Launcher"
        return 0
    }

    log "Epic Games Launcher launched"
    return 0
}

# Other Gaming Launchers
provider_other_launchers() {
    log "=== Provider: Other Gaming Launchers ==="

    if ! $INSTALL_UPDATES && ! $DRY_RUN; then
        return 0
    fi

    local launchers=(
        "GOG Galaxy:/Applications/GOG Galaxy.app:GalaxyClient"
        "Battle.net:/Applications/Battle.net.app:Battle.net"
    )

    for entry in "${launchers[@]}"; do
        IFS=':' read -r name app_path process_name <<< "$entry"
        if [[ -d "$app_path" ]]; then
            if is_process_running "$process_name"; then
                log "$name already running, skipping"
                continue
            fi
            if $DRY_RUN; then
                log "DRY-RUN: Would launch $name"
                continue
            fi
            log "Launching $name for updates..."
            run_with_timeout "$TIMEOUT_THIRD_PARTY" \
                open -g -a "$app_path" 2>&1 || warn "Failed to launch $name"
        fi
    done

    return 0
}

# Third-party applications via Homebrew Cask (already covered by provider_homebrew)
# This provider handles apps with their own updaters not covered by Homebrew
provider_third_party() {
    log "=== Provider: Third-Party Applications ==="

    if ! $INSTALL_UPDATES && ! $DRY_RUN; then
        return 0
    fi

    # Most third-party apps on macOS are updated via:
    # 1. Homebrew Cask (covered above)
    # 2. Sparkle framework (auto-updates when app runs)
    # 3. Built-in updaters (triggered on app launch)
    # 4. Mac App Store (covered above)
    #
    # We don't implement per-app updaters to avoid:
    # - Reverse-engineering proprietary protocols
    # - Downloading from unofficial sources
    # - Breaking code signing/notarization
    #
    # Apps with Sparkle/built-in updaters will update when user launches them.

    if $DRY_RUN; then
        log "DRY-RUN: Third-party apps update via Homebrew Cask / Sparkle / built-in"
    fi

    log "Third-party apps: relying on Homebrew Cask, Sparkle, and built-in updaters"
    return 0
}

# ─── Main Execution ──────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    log "Starting $SCRIPT_NAME (require_network=$REQUIRE_NETWORK, install=$INSTALL_UPDATES, dry_run=$DRY_RUN)"

    # Check daily run (skip if already ran today)
    if ! check_daily_run; then
        exit 0
    fi

    # Acquire lock
    if ! acquire_lock; then
        log "Another update process is running, exiting"
        exit 0
    fi

    # Network check
    if ! check_network; then
        exit 0
    fi

    # Run providers in priority order
    # Each provider is independent - failures don't stop the pipeline
    provider_macos_update         || true
    provider_app_store            || true
    provider_homebrew             || true
    provider_nvidia               || true
    provider_steam                || true
    provider_epic                 || true
    provider_other_launchers      || true
    provider_third_party          || true

    log "All update providers completed"
}

main "$@"