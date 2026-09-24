# Universal Silent macOS Update Automator

A native macOS automation system that silently keeps macOS, system software, Mac App Store applications, Homebrew packages and casks, and supported gaming launchers and third-party applications up to date.

The project runs automatically in the background using **macOS LaunchAgent**, checks for network connectivity, prevents concurrent executions, uses provider-specific timeouts, and avoids forced restarts or destructive system modifications.

> **Important:** This project does not claim to update every macOS application. It uses supported or established update mechanisms and gracefully skips software that cannot be safely updated without user interaction.

---

## Features

* 🍎 macOS system and security updates
* 🏪 Mac App Store application updates through `mas`
* 🍺 Homebrew package updates
* 📦 Homebrew Cask application updates
* 🎮 Steam update support
* 🎮 Epic Games Launcher support
* 🎮 GOG Galaxy detection
* 🎮 Battle.net detection
* 🖥️ NVIDIA hardware/software detection
* 📶 Network-aware execution
* 🔒 Concurrent execution protection
* ⏱️ Provider-specific timeout protection
* 🤫 Background execution through `launchd`
* 🔋 Apple Silicon and Intel support
* 🧪 Dry-run mode
* 🚫 No forced macOS restart
* 🚫 No persistent logs or reports
* 🛡️ No security bypasses
* 🔐 No Apple ID or sudo password storage

---

## Architecture

```text
                 macOS LaunchAgent
                       │
                       │ Every 6 hours
                       ▼
          StartupUpdateCheck.sh
                       │
                       ▼
              Acquire Lock
                       │
                       ▼
          Check Network Connectivity
                       │
                       ▼
              Update Providers
                       │
       ┌───────────────┼────────────────┐
       ▼               ▼                ▼
 macOS Update      App Store        Homebrew
       │               │                │
       └───────────────┼────────────────┘
                       │
       ┌───────────────┼────────────────┐
       ▼               ▼                ▼
     NVIDIA           Steam            Epic
       │               │                │
       └───────────────┼────────────────┘
                       │
                       ▼
             Other Launchers
                       │
                       ▼
              Third-Party Apps
                       │
                       ▼
                Release Lock
                       │
                       ▼
                 Exit Silently
```

---

## Project Structure

```text
Universal-Silent-macOS-Update-Automator/
│
├── StartupUpdateCheck.sh
├── Register-StartupUpdateCheck.sh
├── Unregister-StartupUpdateCheck.sh
│
├── launchd/
│   └── com.codex.backgroundupdatecheck.plist
│
├── README.md
├── .gitignore
└── LICENSE
```

### Components

| File                                    | Purpose                                |
| --------------------------------------- | -------------------------------------- |
| `StartupUpdateCheck.sh`                 | Main update engine                     |
| `Register-StartupUpdateCheck.sh`        | Installs and registers the LaunchAgent |
| `Unregister-StartupUpdateCheck.sh`      | Removes the LaunchAgent                |
| `com.codex.backgroundupdatecheck.plist` | macOS `launchd` configuration          |
| `README.md`                             | Project documentation                  |
| `.gitignore`                            | Git exclusions                         |
| `LICENSE`                               | MIT License                            |

---

# Update Providers

The update engine contains nine provider paths.

## 1. macOS System Updates

**Status:** ✅ Supported

Uses Apple's native:

```bash
/usr/sbin/softwareupdate
```

The implementation uses:

```bash
softwareupdate -i -a --agree-to-license --no-scan
```

The updater does not use a restart flag.

If an update requires a restart, the update can be installed while the restart remains the user's responsibility.

Dry-run/check-only mode uses:

```bash
softwareupdate -l
```

---

## 2. Mac App Store

**Status:** ⚠️ Conditional

Uses:

```text
mas
```

The project can execute:

```bash
mas upgrade
```

when `mas` is available.

### Limitation

Many App Store updates require Apple ID authentication.

If authentication prevents unattended updating, the provider exits gracefully rather than attempting to bypass authentication.

---

## 3. Homebrew

**Status:** ✅ Supported

The project automatically detects Homebrew on both architectures.

### Apple Silicon

```text
/opt/homebrew/bin/brew
```

### Intel

```text
/usr/local/bin/brew
```

The update sequence includes:

```bash
brew update
brew upgrade
brew upgrade --cask
```

Old Homebrew versions may also be cleaned using:

```bash
brew cleanup --prune=all
```

The provider checks for an existing Homebrew process before starting another update operation.

---

## 4. NVIDIA

**Status:** ❌ Generally Not Applicable

The project detects NVIDIA hardware using:

```bash
system_profiler SPDisplaysDataType
```

NVIDIA updating is skipped where modern macOS does not provide applicable driver support.

This is particularly relevant for Apple Silicon Macs, where NVIDIA GPU driver installation is not applicable.

The project does not download unofficial NVIDIA drivers or bypass Apple's driver/security architecture.

---

## 5. Steam

**Status:** ⚠️ Best-Effort

Steam is detected at:

```text
/Applications/Steam.app
```

When Steam is installed and not already running, the project can launch it in the background using:

```bash
open -g -a "/Applications/Steam.app"
```

If Steam is already running, the updater does not start another instance.

### Important

The macOS implementation does not assume Windows-specific Steam flags such as:

```text
-silent
```

Steam itself is responsible for its supported client and game update behavior.

---

## 6. Epic Games Launcher

**Status:** ⚠️ Best-Effort

Detects:

```text
/Applications/Epic Games Launcher.app
```

The launcher can be opened in the background using:

```bash
open -g -a "/Applications/Epic Games Launcher.app"
```

If Epic Games Launcher is already running, another instance is not started.

The project does not terminate running games or manipulate Epic's internal update system.

---

## 7. Other Gaming Launchers

**Status:** ⚠️ Best-Effort

The current implementation includes detection paths for:

### GOG Galaxy

```text
/Applications/GOG Galaxy.app
```

### Battle.net

```text
/Applications/Battle.net.app
```

Launchers are only started when detected and not already running.

The project does not claim guaranteed unattended updates for launchers that do not provide an appropriate background update mechanism.

---

## 8. Third-Party Applications

**Status:** ⚠️ Conditional

Third-party applications are primarily handled through:

* Homebrew Cask
* Application/vendor update mechanisms
* Sparkle-based application updaters where applicable

The project deliberately avoids custom reverse-engineered update logic for individual applications.

This allows applications supported by Homebrew Cask to be updated through the established Homebrew ecosystem.

---

# Network Detection

macOS does not provide a direct equivalent of the Windows NetworkProfile Event ID 10000 used by the Windows version of this project.

Instead, this project uses general network connectivity checks.

The implementation checks multiple targets, including:

```text
8.8.8.8
1.1.1.1
Default gateway
```

The update engine supports:

```bash
--require-network
```

When network connectivity is unavailable, the update process exits without attempting large update operations.

---

# Automatic Execution

The project uses Apple's:

```text
launchd
```

rather than Windows Task Scheduler.

The LaunchAgent is:

```text
com.codex.backgroundupdatecheck
```

The default schedule is:

```text
Every 6 hours
```

using:

```text
StartInterval = 21600
```

It also uses:

```text
RunAtLoad = true
KeepAlive = false
ThrottleInterval = 3600
ProcessType = Background
```

Standard output and error are redirected to:

```text
/dev/null
```

to maintain silent operation.

---

# Concurrency Protection

The update engine uses an atomic directory lock:

```text
/tmp/com.codex.backgroundupdatecheck.lock
```

This prevents multiple copies of the updater from running simultaneously.

Example:

```text
Updater A
    │
    ├── Acquires lock
    │
    └── Runs updates


Updater B
    │
    ├── Attempts lock
    │
    └── Exits because lock is already held
```

Locks older than the configured stale threshold can be removed automatically.

The script also uses cleanup traps so that the lock is released when the process exits.

---

# Timeout Protection

Every update provider has timeout protection.

| Provider            |    Timeout |
| ------------------- | ---------: |
| macOS System Update | 30 minutes |
| Mac App Store       | 15 minutes |
| Homebrew            | 15 minutes |
| Steam               | 15 minutes |
| Epic Games          | 15 minutes |
| Other Launchers     | 15 minutes |
| Third-Party Updates | 15 minutes |

The implementation uses the available `timeout` mechanism and a Perl `alarm` fallback where required.

A provider timing out does not terminate the entire update pipeline.

---

# Installation

Clone the repository:

```bash
git clone <repo-url>
```

Enter the directory:

```bash
cd Universal-Silent-macOS-Update-Automator
```

Make the scripts executable if necessary:

```bash
chmod +x StartupUpdateCheck.sh
chmod +x Register-StartupUpdateCheck.sh
chmod +x Unregister-StartupUpdateCheck.sh
```

Install the LaunchAgent:

```bash
./Register-StartupUpdateCheck.sh
```

Run the installation as the normal user.

**Do not run the installer as root unless the implementation specifically requires it.**

The installer places the update engine under:

```text
~/.local/share/codex-background-update/
```

and installs the LaunchAgent under:

```text
~/Library/LaunchAgents/
```

---

# Manual Testing

## Check for Updates

Run:

```bash
./StartupUpdateCheck.sh
```

---

## Full Update Run

Run:

```bash
./StartupUpdateCheck.sh --require-network --install-updates
```

This enables network checking and update installation.

---

## Dry Run

Run:

```bash
./StartupUpdateCheck.sh --dry-run
```

Dry-run mode is intended to show what the updater would attempt without installing updates.

---

## Help

Run:

```bash
./StartupUpdateCheck.sh --help
```

---

# Uninstallation

Run:

```bash
./Unregister-StartupUpdateCheck.sh
```

The uninstaller:

1. Unloads the LaunchAgent.
2. Removes the LaunchAgent configuration.
3. Removes the installed update-engine directory.
4. Cleans the project's stale lock.

It does not remove unrelated launchd jobs or applications.

---

# Compatibility

## macOS

| Version              | Status      |
| -------------------- | ----------- |
| macOS 15 Sequoia     | ✅ Tested    |
| macOS 14 Sonoma      | ✅ Tested    |
| macOS 13 Ventura     | ✅ Tested    |
| macOS 12 Monterey    | ✅ Tested    |
| macOS 11 Big Sur     | ✅ Supported |
| macOS 10.15 Catalina | ⚠️ Limited  |

Catalina has limitations around the availability of the `timeout` command, for which the project provides a Perl-based fallback.

---

## Hardware Architecture

| Architecture            | Status           |
| ----------------------- | ---------------- |
| Apple Silicon — `arm64` | ✅ Primary target |
| Intel — `x86_64`        | ✅ Supported      |

Homebrew installation paths are automatically detected for both architectures.

---

# Security

Security is a core design principle of the project.

The updater does **not**:

* Disable System Integrity Protection
* Disable Gatekeeper
* Disable XProtect
* Disable FileVault
* Disable macOS security controls
* Store Apple ID passwords
* Store sudo passwords
* Automate password entry
* Download unofficial software
* Install unofficial drivers
* Modify application bundles
* Modify application databases
* Reverse-engineer proprietary update protocols
* Kill user processes
* Force applications to quit
* Force restart macOS

The project uses Apple and established package-management mechanisms wherever possible.

---

# User Activity Protection

The updater is designed to avoid disrupting active work or gaming sessions.

It does not intentionally:

* Kill applications
* Kill games
* Close Steam
* Close Epic Games Launcher
* Interrupt active downloads
* Force applications to quit
* Restart macOS

For launchers such as Steam and Epic, the project first checks whether the application is already running.

---

# Limitations

## Mac App Store Authentication

`mas` may require Apple ID authentication.

The project does not store credentials or attempt to bypass authentication.

---

## NVIDIA

NVIDIA GPU driver support is generally not applicable to modern macOS systems.

The project therefore detects NVIDIA hardware and skips unsupported configurations rather than attempting unsafe driver installation.

---

## Steam and Epic

Neither launcher should be assumed to provide Windows-style silent command-line arguments on macOS.

The project uses:

```bash
open -g
```

as a best-effort background launch mechanism.

The launcher itself remains responsible for its supported update behavior.

---

## GUI-Only Applications

Applications that require GUI interaction for updating may be skipped.

Examples can include applications whose updater requires:

* Login
* Authentication
* User confirmation
* Accessibility interaction
* License acceptance

The project deliberately does not automate mouse clicks or keyboard input to bypass these requirements.

---

## Reboot-Required Updates

Some macOS updates require a restart.

The project does not force the restart.

The user remains responsible for restarting the Mac when appropriate.

---

# Supported Third-Party Software Through Homebrew Cask

Homebrew Cask provides support for a large number of macOS applications.

Examples include categories such as:

### Browsers

* Google Chrome
* Mozilla Firefox
* Microsoft Edge
* Brave

### Development

* Visual Studio Code
* Docker Desktop
* iTerm2
* GitHub Desktop

### Communication

* Slack
* Discord
* Zoom
* Microsoft Teams

### Productivity

* Notion
* Obsidian
* 1Password
* Rectangle

### Creative

* Figma
* Blender
* VLC
* OBS

### Cloud

* Dropbox
* Google Drive
* OneDrive

Actual update availability depends on Homebrew Cask support and the installed application's packaging.

---

# Design Philosophy

The project follows one core principle:

> **Maximum practical update coverage with minimum risk.**

Instead of attempting to update every application through hacks or reverse-engineered mechanisms, the updater combines native macOS tools, established package managers, and supported vendor mechanisms.

If an application cannot safely be updated unattended, the project skips it.

---

# What This Project Does NOT Do

* ❌ Force macOS to restart
* ❌ Generate persistent reports or logs
* ❌ Create update history files
* ❌ Download unofficial software
* ❌ Install unofficial drivers
* ❌ Modify application bundles
* ❌ Modify application databases
* ❌ Kill user processes
* ❌ Interrupt running games
* ❌ Interrupt active downloads
* ❌ Disable SIP
* ❌ Disable Gatekeeper
* ❌ Disable XProtect
* ❌ Disable FileVault
* ❌ Store Apple ID credentials
* ❌ Store sudo credentials
* ❌ Bypass authentication
* ❌ Claim universal application coverage

---

# Validation

The project includes validation for:

* Bash syntax
* Executable permissions
* LaunchAgent configuration
* macOS paths
* Apple Silicon Homebrew paths
* Intel Homebrew paths
* Network detection
* Concurrency locking
* Timeout fallback
* Process detection
* Error isolation
* Dry-run mode
* Help output

Example syntax validation:

```bash
bash -n StartupUpdateCheck.sh
```

---

# GitHub Project Structure

The final repository should contain:

```text
Universal-Silent-macOS-Update-Automator/
│
├── StartupUpdateCheck.sh
├── Register-StartupUpdateCheck.sh
├── Unregister-StartupUpdateCheck.sh
│
├── launchd/
│   └── com.codex.backgroundupdatecheck.plist
│
├── README.md
├── .gitignore
└── LICENSE
```

---

# License

This project is released under the **MIT License**.

See `LICENSE` for the complete license text.

---

## Disclaimer

This software performs automated system and application update operations.

Update behavior can change when Apple, Homebrew, or third-party software vendors modify their update mechanisms.

Always test the project on your own Mac before relying on unattended updates.

The project intentionally favors safe, supported update mechanisms over maximum update coverage.

---

**Built with Bash and native macOS automation.**
