# Niri Dotfiles

A minimal, reproducible **Niri (Wayland) desktop setup** focused on performance, simplicity, and clean UX.

This repository provides:
- A complete Wayland environment (Niri + Waybar + Fuzzel + Mako)
- A modular install script with bootstrap, update, and rollback support
- Optional symlink-based deployment for easy maintenance
- A clean and lightweight workflow optimized for low-resource systems

## Table of Contents
- [Design Goals](#design-goals)
- [Installation](#installation)
- [Installer Commands](#installer-commands)
- [Quick Examples](#quick-examples)
- [Manual Installation](#manual-installation)
- [Repository Layout](#repository-layout)
- [Preview](#preview)

## Design Goals
Designed to be:
- **Fast**: Minimal overhead for maximum performance.
- **Minimal**: Only the essential tools for a productive environment.
- **Reproducible**: Easy to deploy across different machines.
- **Modifiable**: Simple structure that is easy to understand and tweak.

## Installation

Clone the repo and run the installer from inside the project directory.

```bash
git clone https://github.com/l7p3x/dotfile-niri.git ~/.local/share/dotfile-niri
cd ~/.local/share/dotfile-niri
./install.sh
```

The default run uses the `auto` flow (`bootstrap + install`).

### Warning
The installer can deploy files in two modes:
- **default**: copies files to your `$HOME`
- **--symlink**: symlinks files from this repo into your `$HOME` (do not move or delete the repo folder after installation).

## Installer Commands
```bash
./install.sh --help
```

| Command | Description |
| :--- | :--- |
| `(none)` | Full auto: bootstrap + install |
| `bootstrap` | Install base system from scratch |
| `install` | Deploy dotfiles |
| `update` | Re-deploy only changed files |
| `rollback` | Restore last backed-up files |
| `status` | Show current install state |

### Options
- `--install-packages`: Install packages via yay/pacman
- `--symlink`: Use symlinks instead of copies
- `--no-backup`: Skip backup
- `--dry-run`: Show actions without changing anything
- `--force`: Ignore install lock
- `--yes`: Non-interactive mode
- `--profile=NAME`: Use a profile name

## Quick Examples

**Full setup:**
```bash
./install.sh
```

**Only bootstrap dependencies:**
```bash
./install.sh bootstrap
```

**Install configs with symlinks:**
```bash
./install.sh install --symlink
```

**Update after pulling new changes:**
```bash
git pull
./install.sh update
```

**Check current state:**
```bash
./install.sh status
```

**Rollback backups created during deploy:**
```bash
./install.sh rollback
```

## Manual Installation

If you want to do everything manually:
1. Install core dependencies (Niri, Waybar, Fuzzel, Mako, Fish, Alacritty, Thunar, fonts, etc.).
2. Copy or symlink this repo's `.config/` entries to `~/.config/`.
3. Copy or symlink `.local/bin/` scripts to `~/.local/bin/`.
4. Copy `.local/share/applications/`, `.local/share/icons/`, and `.local/share/fonts/` into your local share directory.
5. Log out and log back in.

## Repository Layout
- `.config/` → App configs (niri, waybar, fish, mako, fuzzel, alacritty, etc.)
- `.local/bin/` → Helper scripts
- `.local/share/` → Local desktop assets (icons, desktop files, fonts)
- `Wallpaper/` → Wallpaper collection
- `screenshots/` → Preview images and video
- `install.sh` → Installer and update/rollback/status workflow

## Preview

| Desktop | Terminal |
|---|---|
| ![Desktop](screenshots/desktop.png) | ![Terminal](screenshots/terminal.png) |

| Fuzzel | Alt desktop |
|---|---|
| ![Fuzzel](screenshots/fuzzel.png) | ![Desktop 2](screenshots/desktop2.png) |

Video: [`screenshots/preview.mp4`](screenshots/preview.mp4)
