#!/usr/bin/env bash
# =============================================================================
#  install.sh — Dotfile manager  (Niri + Wayland + fish)
#
#  Commands:  bootstrap · install · update · rollback · status
#
#  bootstrap   Install base system (base-devel → yay → core pkgs)
#  install     Deploy configs (assumes bootstrap done or --install-packages)
#  update      Re-deploy only changed files
#  rollback    Restore last backed-up files
#  status      Show current install state
#
#  Idempotent · State-aware · Rollback-capable · Profile-ready
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Resolve script root (safe against symlinks) ───────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
C_RESET='\033[0m';    C_BOLD='\033[1m';      C_DIM='\033[2m'
C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'
C_RED='\033[0;31m';   C_CYAN='\033[0;36m';   C_MAGENTA='\033[0;35m'

# ── Logging ───────────────────────────────────────────────────────────────────
info()    { echo -e "${C_BLUE}${C_BOLD}  =>${C_RESET} $*"; }
ok()      { echo -e "${C_GREEN}${C_BOLD}  ✓${C_RESET}  $*"; }
skip()    { echo -e "${C_DIM}  –  $*${C_RESET}"; }
warn()    { echo -e "${C_YELLOW}${C_BOLD}  !${C_RESET}  $*"; }
err()     { echo -e "${C_RED}${C_BOLD}  ✗${C_RESET}  $*" >&2; }
section() { echo -e "\n${C_CYAN}${C_BOLD}━━━  $*  ━━━${C_RESET}"; }
changed() { echo -e "${C_MAGENTA}${C_BOLD}  ~${C_RESET}  $*"; }
ask()     { echo -en "${C_YELLOW}${C_BOLD}  ?${C_RESET}  $*"; }

# =============================================================================
#  STATE  (single source of truth — all paths derived from STATE_DIR)
# =============================================================================
STATE_DIR="$HOME/.local/state/dotfiles"

_sf()            { echo "$STATE_DIR/$1"; }
state::init()    { mkdir -p "$STATE_DIR"; }
state::log()     { $FLAG_DRY_RUN && return; echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$(_sf changes.log)"; }
state::get()     { local f; f="$(_sf "$1")"; [[ -f "$f" ]] && cat "$f" || echo ""; }
state::set()     { $FLAG_DRY_RUN && return; echo "$2" > "$(_sf "$1")"; }
state::exists()  { [[ -f "$(_sf "$1")" ]]; }
state::append()  { $FLAG_DRY_RUN && return; echo "$2" >> "$(_sf "$1")"; }
state::clear()   { $FLAG_DRY_RUN && return; > "$(_sf "$1")"; }

state::set_lock() {
  $FLAG_DRY_RUN && return
  cat > "$(_sf install.lock)" <<EOF
installed_at=$(date '+%Y-%m-%d %H:%M:%S')
profile=$PROFILE
symlink=$FLAG_SYMLINK
script_dir=$SCRIPT_DIR
EOF
  state::log "LOCK set (profile=$PROFILE)"
}

# =============================================================================
#  FLAGS
# =============================================================================
FLAG_INSTALL_PKGS=false
FLAG_SYMLINK=false
FLAG_NO_BACKUP=true
FLAG_DRY_RUN=false
FLAG_FORCE=false
FLAG_YES=false
PROFILE="default"
COMMAND="auto"

# =============================================================================
#  CLI
# =============================================================================
usage() {
  cat <<EOF

Usage:  $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  (none)              Full auto: bootstrap + install (recommended for new users)
  bootstrap           Install base system from scratch (base-devel → yay → core)
  install             Deploy dotfiles
  update              Re-deploy only changed files
  rollback            Restore last backed-up files
  status              Show current install state

Options:
  --install-packages  Install packages via yay/pacman
  --symlink           Use symlinks instead of copies for configs
  --no-backup         Skip backup (overwrite directly)
  --dry-run           Show what would be done, do nothing
  --force             Ignore install lock, re-run fully
  --yes               Non-interactive mode
  --profile NAME      Use a named profile (default: "default")
  -h, --help          This message

Quick start (just clone and run):
  git clone https://github.com/l7p3x/dotfile-niri.git
  cd dotfile-niri && ./install.sh

EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    bootstrap|install|update|rollback|status|auto) COMMAND="$arg" ;;
    --install-packages) FLAG_INSTALL_PKGS=true ;;
    --symlink)          FLAG_SYMLINK=true ;;
    --no-backup)        FLAG_NO_BACKUP=true ;;
    --dry-run)          FLAG_DRY_RUN=true ;;
    --force)            FLAG_FORCE=true ;;
    --yes)              FLAG_YES=true ;;
    --profile=*)        PROFILE="${arg#--profile=}" ;;
    -h|--help)          usage ;;
    *) err "Unknown argument: $arg"; usage ;;
  esac
done

# ── Dry-run wrapper ───────────────────────────────────────────────────────────
run() {
  if $FLAG_DRY_RUN; then
    echo -e "${C_DIM}     [dry] $*${C_RESET}"
    return 0
  else
    "$@"
  fi
}

# ── Interactive confirm (respects --yes and --dry-run) ───────────────────────
# Requer que o usuário digite "y" (ou "Y") e pressione Enter para confirmar.
# Um único caractere sem Enter não é aceito — evita confirmações acidentais.
confirm() {
  $FLAG_DRY_RUN && return 0
  $FLAG_YES     && return 0
  ask "$1 [y/N] "; read -r reply; echo
  [[ "$reply" =~ ^[Yy]$ ]]
}

# =============================================================================
#  PACKAGE MANAGER ABSTRACTION
# =============================================================================
PKG_MANAGER="none"

_detect_pkg_manager() {
  command -v yay    &>/dev/null && PKG_MANAGER="yay"    && return
  command -v pacman &>/dev/null && PKG_MANAGER="pacman" && return
  PKG_MANAGER="none"
}

is_pkg_installed() {
  if command -v pacman &>/dev/null; then
    pacman -Qq "$1" &>/dev/null
  else
    command -v "$1" &>/dev/null
  fi
}

pkg_install() {
  local to_install=()
  for pkg in "$@"; do
    is_pkg_installed "$pkg" && skip "$pkg (installed)" || to_install+=("$pkg")
  done
  [[ ${#to_install[@]} -eq 0 ]] && return 0

  info "Installing: ${to_install[*]}"
  case "$PKG_MANAGER" in
    yay)    run yay    -S --needed --noconfirm "${to_install[@]}" ;;
    pacman) run sudo pacman -S --needed --noconfirm "${to_install[@]}" ;;
    none)   err "No package manager available."; return 1 ;;
  esac
  ok "${#to_install[@]} packages installed."
  state::log "PKGS installed: ${to_install[*]}"
}

# =============================================================================
#  DEPLOY HELPERS
# =============================================================================
safe_backup() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0

  if ! $FLAG_NO_BACKUP; then
    local bak="${target}.bak"
    [[ -e "$bak" ]] && rm -rf "$bak"
    run mv "$target" "$bak"
    state::append "backup.index" "$target|$bak"
    warn "Backed up: $(basename "$target") → $bak"
  else
    run rm -rf "$target"
    skip "Removed (--no-backup): $target"
  fi
}

deploy_entry() {
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then warn "Not found, skipping: $src"; return 1; fi

  if ! $FLAG_FORCE && ! $FLAG_SYMLINK; then
    if [[ -e "$dst" ]] && diff -rq --no-dereference "$src" "$dst" &>/dev/null; then
      skip "Unchanged: $(basename "$dst")"; return 0
    fi
  fi

  safe_backup "$dst"

  if $FLAG_SYMLINK; then
    run ln -sf "$src" "$dst"; changed "Symlinked: $dst"
  else
    run cp -r "$src" "$dst"; changed "Copied:    $dst"
  fi
  state::log "DEPLOY $dst (symlink=$FLAG_SYMLINK)"
}

# =============================================================================
#  REQUIRED BINARIES CHECK
# =============================================================================
REQUIRED_BINS=(
  git wget alacritty btop
  waybar fuzzel mako niri
  grim wl-copy brightnessctl
  xdg-user-dirs-update
)

check_required_bins() {
  section "Runtime validation"
  local missing=()
  for bin in "${REQUIRED_BINS[@]}"; do
    command -v "$bin" &>/dev/null && skip "$bin" || { warn "Missing: $bin"; missing+=("$bin"); }
  done
  [[ ${#missing[@]} -gt 0 ]] \
    && warn "${#missing[@]} missing — run: $(basename "$0") bootstrap" \
    || ok "All required binaries present."
}

# =============================================================================
#  COMMAND: bootstrap
#  Goal: raw Arch install → yay + fonts + fish + plugins + packages
# =============================================================================
cmd_bootstrap() {
  section "Bootstrap — Arch base → yay → packages"

  ! command -v pacman &>/dev/null && { err "pacman not found. Arch only."; exit 1; }
  [[ "$EUID" -eq 0 ]]             && { err "Do not run as root. sudo is used internally."; exit 1; }
  sudo -v &>/dev/null             || { err "sudo not available or credentials failed."; exit 1; }
  ok "sudo access confirmed."

  if state::exists "bootstrap.done" && ! $FLAG_FORCE; then
    warn "Bootstrap already done: $(state::get 'bootstrap.done')"
    warn "Use --force to re-run."; return 0
  fi

  # ── B1: base-devel + git via pacman ────────────────────────────────────────
  section "B1 · base-devel + git"
  _detect_pkg_manager

  local BASE_DEPS=(base-devel git curl wget)
  local missing_base=()
  for pkg in "${BASE_DEPS[@]}"; do
    is_pkg_installed "$pkg" && skip "$pkg" || missing_base+=("$pkg")
  done

  if [[ ${#missing_base[@]} -gt 0 ]]; then
    info "pacman: installing ${missing_base[*]}"
    run sudo pacman -S --needed --noconfirm "${missing_base[@]}"
    ok "Base dependencies installed."
  else
    ok "Base dependencies already present."
  fi

  # ── B2: yay from AUR ──────────────────────────────────────────────────────
  section "B2 · yay (AUR helper)"

  if command -v yay &>/dev/null && ! $FLAG_FORCE; then
    skip "yay already installed."
  else
    info "Cloning and building yay-bin from AUR…"
    local tmp_dir; tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    run git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp_dir/yay-bin"
    if ! $FLAG_DRY_RUN; then
      (cd "$tmp_dir/yay-bin" && makepkg -si --noconfirm)
    fi
    trap - EXIT
    run rm -rf "$tmp_dir"
    ok "yay installed."
    state::log "BOOTSTRAP yay installed"
  fi
  PKG_MANAGER="yay"

  # ── B3: core packages via yay ──────────────────────────────────────────────
  section "B3 · Core packages"

  pkg_install \
    git curl wget xdg-utils xdg-user-dirs \
    fish alacritty btop fastfetch \
    waybar fuzzel mako niri \
    grim slurp wl-clipboard brightnessctl \
    mpv imv ripgrep \
    thunar nwg-look swaylock cava xsettingsd \
    ttf-jetbrains-mono-nerd \
    ttf-nerd-fonts-symbols  \
    noto-fonts \
    noto-fonts-emoji \
    ttf-liberation \
    qogir-cursor-theme \
    gruvbox-dark-gtk \
    gruvbox-dark-icons-gtk

  if command -v fc-cache &>/dev/null; then
    run fc-cache -fv &>/dev/null
    ok "Font cache rebuilt."
  fi

  # ── B4: fish como shell padrão ─────────────────────────────────────────────
  section "B4 · Default shell → fish"

  if command -v fish &>/dev/null; then
    local fish_bin; fish_bin="$(command -v fish)"

    if ! grep -qF "$fish_bin" /etc/shells 2>/dev/null; then
      info "Adding fish to /etc/shells…"
      run bash -c "echo '$fish_bin' | sudo tee -a /etc/shells > /dev/null"
    fi

    local current_shell; current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$current_shell" != "$fish_bin" ]]; then
      run sudo chsh -s "$fish_bin" "$USER"
      ok "Default shell → fish (re-login required)"
      state::log "SHELL changed to fish"
    else
      skip "Shell already fish."
    fi
  else
    warn "fish not found — skipping shell change."
  fi

  # ── B5: Fisher + plugins ───────────────────────────────────────────────────
  section "B5 · Fisher (fish plugin manager)"

  local plugin_list="$SCRIPT_DIR/fish/plugins.txt"
  local -a FISHER_PLUGINS=(
    PatrickF1/fzf.fish
    jorgebucaran/autopair.fish
    meaningful-ooo/sponge
    nickeb96/puffer-fish
  )
  if [[ -f "$plugin_list" ]]; then
    mapfile -t FISHER_PLUGINS < "$plugin_list"
    info "Plugin list from repo: $plugin_list"
  fi

  if command -v fish &>/dev/null; then
    # Instala o fisher primeiro
    if ! fish -c "type -q fisher" &>/dev/null; then
      info "Installing fisher…"
      run fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
      ok "Fisher installed."
      state::log "BOOTSTRAP fisher installed"
    else
      skip "Fisher already installed."
    fi

    # Instala cada plugin (falha em um não para o script)
    for plugin in "${FISHER_PLUGINS[@]}"; do
      [[ -z "$plugin" || "$plugin" == \#* ]] && continue
      if fish -c "fisher list 2>/dev/null | grep -qF '$plugin'"; then
        skip "Plugin: $plugin"
      else
        info "fisher install $plugin"
        if ! $FLAG_DRY_RUN; then
          if fish -c "fisher install $plugin"; then
            ok "Installed: $plugin"
            state::log "PLUGIN $plugin installed"
          else
            warn "Plugin failed (skipping): $plugin"
          fi
        fi
      fi
    done
  else
    warn "fish not available — skipping Fisher setup."
  fi

  # ── B6: XDG user directories ───────────────────────────────────────────────
  section "B6 · XDG user directories"

  if command -v xdg-user-dirs-update &>/dev/null; then
    run xdg-user-dirs-update
    ok "XDG user directories created."
  else
    warn "xdg-user-dirs not found — skipping."
  fi

  # ── B7: git configuration (opcional) ──────────────────────────────────────
  section "B7 · git configuration (optional)"

  local cur_name;  cur_name="$(git  config --global user.name  2>/dev/null || true)"
  local cur_email; cur_email="$(git config --global user.email 2>/dev/null || true)"

  if [[ -n "$cur_name" && -n "$cur_email" ]]; then
    skip "git identity already set: $cur_name <$cur_email>"
  elif $FLAG_YES; then
    # Modo não-interativo: não bloqueia, apenas avisa
    warn "git identity not configured (optional). Set it later with:"
    warn "  git config --global user.name  'Your Name'"
    warn "  git config --global user.email 'your@email.com'"
  else
    # Modo interativo: oferece configurar, mas deixa em branco ser válido
    info "git identity is not set. This is optional — press Enter to skip."
    local git_name="" git_email=""

    ask "git user.name  [Enter to skip]: "; read -r git_name
    ask "git user.email [Enter to skip]: "; read -r git_email

    if [[ -n "$git_name" || -n "$git_email" ]]; then
      [[ -n "$git_name"  ]] && run git config --global user.name  "$git_name"
      [[ -n "$git_email" ]] && run git config --global user.email "$git_email"
      run git config --global init.defaultBranch main
      run git config --global pull.rebase false
      run git config --global core.autocrlf input
      ok "git identity configured."
      state::log "GIT identity set: ${git_name:-<skip>} <${git_email:-<skip>}>"
      state::set "git.configured" "$(date '+%Y-%m-%d %H:%M:%S')"
    else
      skip "git identity skipped — configure manually later if needed."
    fi
  fi

  state::set "bootstrap.done" "$(date '+%Y-%m-%d %H:%M:%S')"
  state::log "BOOTSTRAP complete"

  echo ""
  ok "Bootstrap complete."
  echo ""
  echo -e "  ${C_BOLD}Next:${C_RESET}  $(basename "$0") install --install-packages"
  echo ""
}

# =============================================================================
#  COMMAND: status
# =============================================================================
cmd_status() {
  section "Dotfile Status"
  echo ""

  local lock; lock="$(_sf install.lock)"
  if [[ -f "$lock" ]]; then
    ok "Installed"
    while IFS='=' read -r key val; do
      printf "  ${C_BOLD}%-20s${C_RESET} %s\n" "$key" "$val"
    done < "$lock"
  else
    warn "Not installed (no lock file)"
  fi

  echo ""
  state::exists "bootstrap.done" \
    && ok   "Bootstrap done : $(state::get 'bootstrap.done')" \
    || warn "Bootstrap not done — run: $(basename "$0") bootstrap"

  echo ""
  state::exists "profile.current"   && info "Profile   : $(state::get 'profile.current')"
  state::exists "wallpaper.current" && info "Wallpaper : $(state::get 'wallpaper.current')"
  state::exists "git.configured"    && info "Git setup : $(state::get 'git.configured')"

  echo ""
  local bak; bak="$(_sf backup.index)"
  if [[ -f "$bak" ]]; then
    local n; n=$(wc -l < "$bak")
    [[ $n -gt 0 ]] \
      && info "Backups: $n entries  (run 'rollback' to restore)" \
      || skip "Backup index empty"
  else
    skip "No backup index"
  fi

  echo ""
  local log; log="$(_sf changes.log)"
  if [[ -f "$log" ]]; then
    info "Last 5 log entries:"
    tail -n5 "$log" | while read -r line; do
      echo -e "  ${C_DIM}$line${C_RESET}"
    done
  fi
  echo ""
}

# =============================================================================
#  COMMAND: rollback
# =============================================================================
cmd_rollback() {
  section "Rollback"

  local bak; bak="$(_sf backup.index)"
  [[ -f "$bak" ]] || { err "No backup index — nothing to rollback."; exit 1; }

  local n; n=$(wc -l < "$bak")
  [[ $n -eq 0 ]] && { warn "Backup index is empty."; exit 0; }

  confirm "Restore $n backed-up entries?" || { info "Aborted."; exit 0; }

  while IFS='|' read -r original backup; do
    if [[ -e "$backup" ]]; then
      [[ -e "$original" || -L "$original" ]] && run rm -rf "$original"
      run mv "$backup" "$original"
      ok "Restored: $original"
      state::log "ROLLBACK $original ← $backup"
    else
      warn "Backup missing, skipping: $backup"
    fi
  done < "$bak"

  run rm -f "$bak" "$(_sf install.lock)"
  state::log "ROLLBACK complete — lock removed"
  echo ""
  ok "Rollback complete. Log out and back in."
}

# =============================================================================
#  CORE DEPLOY  (shared by install + update)
# =============================================================================
run_deploy() {

  # ── 0 · Repo guard ──────────────────────────────────────────────────────────
  section "0 · Repo check"
  if [[ ! -d "$SCRIPT_DIR/.config" ]]; then
    err "SCRIPT_DIR/.config not found. Run from the dotfiles repo root."
    err "SCRIPT_DIR=$SCRIPT_DIR"; exit 1
  fi
  ok "Repo valid: $SCRIPT_DIR"

  # ── 1 · Environment ─────────────────────────────────────────────────────────
  section "1 · Environment"
  local OS_ID=""; [[ -f /etc/os-release ]] && OS_ID="$(. /etc/os-release && echo "$ID")"
  _detect_pkg_manager

  info "Distro       : ${OS_ID:-unknown}"
  info "Pkg manager  : $PKG_MANAGER"
  info "Session      : ${XDG_SESSION_TYPE:-tty}"
  info "Shell        : $(basename "$SHELL")"
  info "Profile      : $PROFILE"
  info "Symlink mode : $FLAG_SYMLINK"
  info "Dry-run      : $FLAG_DRY_RUN"

  if [[ "$OS_ID" != "arch" && "$OS_ID" != "manjaro" && \
        "$OS_ID" != "endeavouros" && "$OS_ID" != "cachyos" ]]; then
    warn "Distro '$OS_ID' não é Arch-based — package install desativado."
    FLAG_INSTALL_PKGS=false
  fi

  # ── 2 · Directories ─────────────────────────────────────────────────────────
  section "2 · Directories"
  local DIRS=(
    "$HOME/.config"
    "$HOME/.local/bin"
    "$HOME/.local/share/applications"
    "$HOME/.local/share/wallpaper"
    "$HOME/.local/share/icons"
    "$HOME/.local/share/themes"
    "$HOME/Pictures/Wallpaper"
    "$HOME/.cache"
    "$STATE_DIR"
  )
  for d in "${DIRS[@]}"; do
    [[ -d "$d" ]] && skip "$d" || { run mkdir -p "$d"; ok "Created: $d"; }
  done

  # ── 3 · Packages ────────────────────────────────────────────────────────────
  section "3 · Packages"
  if $FLAG_INSTALL_PKGS; then
    [[ "$PKG_MANAGER" == "none" ]] && { err "No package manager. Run bootstrap first."; } || \
    pkg_install \
      git wget xdg-user-dirs \
      alacritty btop fastfetch \
      waybar fuzzel mako niri \
      grim slurp wl-clipboard brightnessctl \
      mpv imv ripgrep curl \
      ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols noto-fonts noto-fonts-emoji \
      pipewire-pulse wireplumber fish \
      thunar nwg-look swaylock cava xsettingsd \
      gruvbox-dark-gtk gruvbox-dark-icons-gtk qogir-cursor-theme
  else
    warn "Skipping packages (--install-packages not set)"
  fi

  # ── 4 · Configs ─────────────────────────────────────────────────────────────
  section "4 · Configs"
  local base_cfg="$SCRIPT_DIR/.config"
  local profile_cfg="$SCRIPT_DIR/profiles/$PROFILE/.config"
  local -a CONFIG_APPS=(
    alacritty fish waybar fuzzel mako niri
    btop fastfetch cava micro
    gtk-3.0 gtk-4.0 swaylock nwg-look Thunar xsettingsd mpv
  )

  for app in "${CONFIG_APPS[@]}"; do
    local src="$base_cfg/$app"
    [[ -d "$profile_cfg/$app" ]] && src="$profile_cfg/$app" && info "Profile overlay: $app"
    [[ -d "$src" ]] && deploy_entry "$src" "$HOME/.config/$app"
  done

  # ── 4a · .gtkrc-2.0 (home root) ─────────────────────────────────────────────
  section "4a · GTK-2 config"
  local gtkrc2_src="$SCRIPT_DIR/.gtkrc-2.0"
  if [[ -f "$gtkrc2_src" ]]; then
    deploy_entry "$gtkrc2_src" "$HOME/.gtkrc-2.0"
  else
    skip ".gtkrc-2.0 not found in repo."
  fi

  # ── 5 · Wallpapers ──────────────────────────────────────────────────────────
  section "5 · Wallpapers"
  local WALL_SRC="$SCRIPT_DIR/Wallpaper"
  local WALL_DST="$HOME/Pictures/Wallpaper"

  if [[ -d "$WALL_SRC" ]]; then
    run mkdir -p "$WALL_DST"

    if command -v rsync &>/dev/null; then
      # --exclude current.png para não copiar o symlink hardcoded do repo
      run rsync -rlpt --exclude='current.png' "$WALL_SRC/" "$WALL_DST/"
    else
      # copia todos exceto symlinks (current.png)
      find "$WALL_SRC" -maxdepth 1 -type f | while read -r wfile; do
        run cp "$wfile" "$WALL_DST/"
      done
    fi

    run chmod -R u+rw,go+r "$WALL_DST"

    # Escolhe um wallpaper aleatório e cria o symlink current.png
    local first_wall; first_wall="$(find "$WALL_DST" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' \) | shuf | head -n1)"
    local current_link="$HOME/.local/share/wallpaper/current.png"
    if [[ -n "$first_wall" ]]; then
      run ln -sf "$first_wall" "$current_link"

      # Exibe o nome do wallpaper escolhido de forma amigável
      local wall_name; wall_name="$(basename "$first_wall")"
      ok "Wallpaper → $wall_name 🖼"

      # Conta quantos wallpapers estão disponíveis no total
      local wall_count; wall_count="$(find "$WALL_DST" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' \) | wc -l)"
      info "$(printf '%d wallpaper(s) disponível(is) em %s' "$wall_count" "$WALL_DST")"

      state::set "wallpaper.current" "$first_wall"
    else
      warn "Nenhum wallpaper (.png/.jpg) encontrado em $WALL_DST."
    fi

    ok "Wallpapers synced → $WALL_DST"
  else
    warn "No Wallpaper/ directory in repo — skipping."
  fi

  # ── 6 · Scripts → ~/.local/bin ──────────────────────────────────────────────
  section "6 · Scripts"
  local BIN_SRC="$SCRIPT_DIR/.local/bin"
  if [[ -d "$BIN_SRC" ]]; then
    local n=0
    for script in "$BIN_SRC"/*; do
      [[ -f "$script" ]] || continue
      local sname; sname="$(basename "$script")"
      local dst="$HOME/.local/bin/$sname"
      if $FLAG_SYMLINK; then
        run ln -sf "$script" "$dst"; changed "$sname"
      else
        if ! $FLAG_FORCE && [[ -f "$dst" ]] && cmp -s "$script" "$dst"; then
          skip "$sname (unchanged)"; continue
        fi
        safe_backup "$dst"; run cp "$script" "$dst"; changed "$sname"
      fi
      run chmod +x "$dst"; (( n++ )) || true
    done
    [[ $n -gt 0 ]] && ok "Scripts deployed: $n" && state::log "SCRIPTS deployed: $n"
  else
    warn "No .local/bin/ directory — skipping."
  fi

  # ── 6a · .desktop entries → ~/.local/share/applications ──────────────────
  section "6a · Desktop entries"
  local APPS_SRC="$SCRIPT_DIR/.local/share/applications"
  if [[ -d "$APPS_SRC" ]]; then
    local apps_dst="$HOME/.local/share/applications"
    run mkdir -p "$apps_dst"
    local count=0
    for desktop_file in "$APPS_SRC"/*.desktop; do
      [[ -f "$desktop_file" ]] || continue
      local dname; dname="$(basename "$desktop_file")"
      local ddst="$apps_dst/$dname"
      if ! $FLAG_FORCE && [[ -f "$ddst" ]] && cmp -s "$desktop_file" "$ddst"; then
        skip "$dname (unchanged)"; continue
      fi
      safe_backup "$ddst"
      run cp "$desktop_file" "$ddst"; changed "$dname"
      (( count++ )) || true
    done
    [[ $count -gt 0 ]] && ok "Desktop entries deployed: $count" || skip "Desktop entries (all unchanged)"
    state::log "DESKTOP entries deployed: $count"
  else
    skip "No .local/share/applications/ in repo."
  fi

  # ── 6b · Fish configs & plugins ─────────────────────────────────────────────
  section "6b · Fish configs & plugins"
  if command -v fish &>/dev/null; then
    local fish_conf_dir="$HOME/.config/fish/conf.d"
    run mkdir -p "$fish_conf_dir"

    # local-bin.fish
    local fpath_bin="$fish_conf_dir/local-bin.fish"
    if [[ ! -f "$fpath_bin" ]] || $FLAG_FORCE; then
      $FLAG_DRY_RUN || printf '%s\n' \
        '# Added by dotfiles installer' \
        'fish_add_path "$HOME/.local/bin"' > "$fpath_bin"
      ok "fish PATH conf written ($fpath_bin)."
    else
      skip "fish PATH conf (unchanged)"
    fi

    # xdg.fish
    local fpath_xdg="$fish_conf_dir/xdg.fish"
    if [[ ! -f "$fpath_xdg" ]] || $FLAG_FORCE; then
      $FLAG_DRY_RUN || printf '%s\n' \
        '# Added by dotfiles installer' \
        'set -q XDG_CONFIG_HOME; or set -gx XDG_CONFIG_HOME $HOME/.config' \
        'set -q XDG_DATA_HOME;   or set -gx XDG_DATA_HOME   $HOME/.local/share' \
        'set -q XDG_STATE_HOME;  or set -gx XDG_STATE_HOME  $HOME/.local/state' \
        'set -q XDG_CACHE_HOME;  or set -gx XDG_CACHE_HOME  $HOME/.cache' > "$fpath_xdg"
      ok "fish XDG conf written ($fpath_xdg)."
    else
      skip "fish XDG conf (unchanged)"
    fi

    # Fisher: instala se não estiver presente, depois atualiza
    if ! fish -c "type -q fisher" &>/dev/null; then
      info "Fisher não encontrado — instalando..."
      if ! $FLAG_DRY_RUN; then
        fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher" \
          && ok "Fisher installed." \
          || warn "Fisher install returned an error."
      fi
    else
      skip "Fisher already installed."
    fi

    # fisher update — só executa se existir fish_plugins com conteúdo
    local fish_plugins="$HOME/.config/fish/fish_plugins"
    if [[ -f "$fish_plugins" ]] && [[ -s "$fish_plugins" ]]; then
      info "Running fisher update..."
      if ! $FLAG_DRY_RUN; then
        if fish -c "fisher update" &>/dev/null; then
          ok "Fisher plugins updated."
          state::log "FISHER update executed"
        else
          warn "Fisher update returned an error."
        fi
      fi
    else
      skip "fish_plugins not found or empty — skipping fisher update (run bootstrap to install plugins)."
    fi
  else
    skip "fish not installed — skipping configs."
  fi

  # ── 6c · Fish como shell padrão ──────────────────────────────────────────
  section "6c · Default shell → fish"
  if command -v fish &>/dev/null; then
    local fish_bin; fish_bin="$(command -v fish)"

    # Garante que fish está em /etc/shells
    if ! grep -qF "$fish_bin" /etc/shells 2>/dev/null; then
      info "Adding fish to /etc/shells…"
      run bash -c "echo '$fish_bin' | sudo tee -a /etc/shells > /dev/null"
    fi

    local current_shell; current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$current_shell" != "$fish_bin" ]]; then
      run sudo chsh -s "$fish_bin" "$USER"
      ok "Default shell → fish (re-login required)"
      state::log "SHELL changed to fish"
    else
      skip "Shell already fish."
    fi
  else
    warn "fish not found — skipping shell change."
  fi

  # ── 7a · Ícones locais ────────────────────────────────────────────────────
  section "7a · Local icons"
  local ICONS_SRC="$SCRIPT_DIR/.local/share/icons"
  if [[ -d "$ICONS_SRC" ]]; then
    local icons_dst="$HOME/.local/share/icons"
    run mkdir -p "$icons_dst"
    run cp -rn "$ICONS_SRC/." "$icons_dst/"
    ok "Icons deployed → $icons_dst"
  else
    skip "No .local/share/icons/ in repo."
  fi

  # ── 7b · nwg-look gsettings ───────────────────────────────────────────────
  section "7b · nwg-look gsettings"
  local NWGLOOK_SRC="$SCRIPT_DIR/.local/share/nwg-look"
  if [[ -d "$NWGLOOK_SRC" ]]; then
    local nwglook_dst="$HOME/.local/share/nwg-look"
    run mkdir -p "$nwglook_dst"
    # usa rsync ou cp -r (sobrescreve, para evitar estado inconsistente)
    if command -v rsync &>/dev/null; then
      run rsync -rlpt "$NWGLOOK_SRC/" "$nwglook_dst/"
    else
      run cp -r "$NWGLOOK_SRC/." "$nwglook_dst/"
    fi
    ok "nwg-look gsettings deployed → $nwglook_dst"
  else
    skip "No .local/share/nwg-look/ in repo."
  fi

  # ── 8 · Systemd user services ─────────────────────────────────────────────
  section "8 · Systemd services"
  local SVC_SRC="$SCRIPT_DIR/systemd"
  if [[ -d "$SVC_SRC" ]]; then
    local svc_dst="$HOME/.config/systemd/user"
    run mkdir -p "$svc_dst"
    for svc in "$SVC_SRC"/*.{service,timer}; do
      [[ -f "$svc" ]] || continue
      local sname; sname="$(basename "$svc")"
      run cp "$svc" "$svc_dst/$sname"
      run systemctl --user daemon-reload 2>/dev/null || true
      run systemctl --user enable "$sname" 2>/dev/null \
        && ok "Enabled: $sname" \
        || warn "Could not enable $sname (needs active user session)"
    done
  else
    skip "No systemd/ directory."
  fi

  # ── 9 · MIME associations ─────────────────────────────────────────────────
  section "9 · MIME"
  local mime_src="$SCRIPT_DIR/mimeapps.list"
  local mime_dst="$HOME/.config/mimeapps.list"

  if [[ -f "$mime_src" ]]; then
    deploy_entry "$mime_src" "$mime_dst"
  elif [[ ! -f "$mime_dst" ]]; then
    $FLAG_DRY_RUN || cat > "$mime_dst" <<'MIME'
[Default Applications]
x-terminal-emulator=alacritty.desktop
inode/directory=thunar.desktop
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
video/webm=mpv.desktop
image/png=imv.desktop
image/jpeg=imv.desktop
image/gif=imv.desktop
image/webp=imv.desktop
MIME
    ok "mimeapps.list: baseline written."
    state::log "MIME baseline written"
  else
    skip "mimeapps.list (unchanged)"
  fi

  # ── 10 · Themes (Gruvbox + Qogir cursor) ────────────────────────────────────
  section "10 · Themes"
  # Temas são instalados via pacote (gruvbox-dark-gtk, gruvbox-dark-icons-gtk,
  # qogir-cursor-theme). Aqui apenas aplicamos via gsettings e xsettingsd.
  # Se a pasta themes/ existir no repo, copia para ~/.local/share/themes/ também.
  local THEME_SRC="$SCRIPT_DIR/themes"
  if [[ -d "$THEME_SRC/icons" ]]; then
    run cp -rn "$THEME_SRC/icons/." "$HOME/.local/share/icons/" 2>/dev/null || true
    ok "Icon theme (repo) installed."
  fi
  if [[ -d "$THEME_SRC/gtk" ]]; then
    run cp -rn "$THEME_SRC/gtk/." "$HOME/.local/share/themes/" 2>/dev/null || true
  fi

  if command -v gsettings &>/dev/null; then
    # GTK theme
    local gtk_theme="Gruvbox-Dark"
    # Detecta o nome exato instalado pelo pacote gruvbox-dark-gtk
    if pacman -Qq gruvbox-dark-gtk &>/dev/null 2>&1; then
      local detected; detected="$(find /usr/share/themes "$HOME/.local/share/themes" \
        -maxdepth 1 -type d -iname 'gruvbox*' 2>/dev/null | head -n1 | xargs basename 2>/dev/null || true)"
      [[ -n "$detected" ]] && gtk_theme="$detected"
    fi

    run gsettings set org.gnome.desktop.interface gtk-theme        "$gtk_theme" 2>/dev/null || true
    run gsettings set org.gnome.desktop.wm.preferences theme       "$gtk_theme" 2>/dev/null || true
    ok "GTK theme → $gtk_theme"

    # Icon theme
    local icon_theme="gruvbox-dark-icons-gtk"
    if pacman -Qq gruvbox-dark-icons-gtk &>/dev/null 2>&1; then
      local det_icon; det_icon="$(find /usr/share/icons "$HOME/.local/share/icons" \
        -maxdepth 1 -type d -iname 'gruvbox*' 2>/dev/null | head -n1 | xargs basename 2>/dev/null || true)"
      [[ -n "$det_icon" ]] && icon_theme="$det_icon"
    fi
    run gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2>/dev/null || true
    ok "Icon theme → $icon_theme"

    # Cursor theme — Qogir-white-cursors como padrão, fallback para Qogir
    local cursor_theme="Qogir-white-cursors"
    if ! find /usr/share/icons "$HOME/.local/share/icons" \
        -maxdepth 1 -type d -name 'Qogir-white-cursors' 2>/dev/null | grep -q .; then
      cursor_theme="Qogir"
    fi
    run gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme" 2>/dev/null || true
    ok "Cursor theme → $cursor_theme"

    state::log "THEMES applied: GTK=$gtk_theme ICONS=$icon_theme CURSOR=$cursor_theme"
  else
    warn "gsettings not available — themes not applied via dconf."
    warn "Install gnome-settings-daemon or use nwg-look to apply themes manually."
  fi

  # ── 10a · Fontes locais ───────────────────────────────────────────────────
  section "10a · Local fonts"
  local FONTS_SRC="$SCRIPT_DIR/.local/share/fonts"
  if [[ -d "$FONTS_SRC" ]]; then
    local fonts_dst="$HOME/.local/share/fonts"
    run mkdir -p "$fonts_dst"
    run cp -rn "$FONTS_SRC/." "$fonts_dst/"
    ok "Fonts deployed → $fonts_dst"

    if command -v fc-cache &>/dev/null; then
      run fc-cache -fv "$fonts_dst" &>/dev/null
      ok "Font cache updated."
    fi
    state::log "FONTS deployed from repo"
  else
    skip "No .local/share/fonts/ in repo."
  fi

  # ── 11 · Weather widget ───────────────────────────────────────────────────
  section "11 · Weather widget"
  # O script está em assets/ (não em scripts/)
  local weather_script="$HOME/.config/waybar/assets/weather.py"

  if [[ -f "$weather_script" ]]; then
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null || curl -s --head --connect-timeout 2 http://google.com &>/dev/null; then
      info "Caching weather location..."
      if ! $FLAG_DRY_RUN; then
        if python3 "$weather_script" &>/dev/null; then
          ok "Weather location cached successfully."
          state::log "WEATHER cached"
        else
          warn "weather.py executed but returned an error."
        fi
      fi
    else
      warn "No internet connection — skipping weather.py cache."
    fi
  else
    skip "weather.py not found in waybar/assets/."
  fi

  # ── 12 · Validation ───────────────────────────────────────────────────────
  check_required_bins

  # ── Persist state ─────────────────────────────────────────────────────────
  # Garante que o symlink de wallpaper (que aponta para path local do usuário)
  # nunca é versionado por acidente
  local gitignore="$SCRIPT_DIR/.gitignore"
  if [[ -f "$gitignore" ]] && ! grep -qF ".local/share/wallpaper" "$gitignore"; then
    echo ".local/share/wallpaper/" >> "$gitignore"
    ok ".gitignore: protegido .local/share/wallpaper/"
  fi

  state::set "profile.current" "$PROFILE"
  state::set_lock
}

# =============================================================================
#  COMMAND: install
# =============================================================================
cmd_install() {
  section "Install — profile: $PROFILE"

  if state::exists "install.lock" && ! $FLAG_FORCE; then
    warn "Already installed. Use 'update' to sync, or --force to re-run."
    exit 0
  fi

  state::clear "backup.index"
  run_deploy

  section "Done"
  echo ""
  printf "  ${C_BOLD}%-16s${C_RESET} %s\n" "Config"  "$HOME/.config"
  printf "  ${C_BOLD}%-16s${C_RESET} %s\n" "Profile" "$PROFILE"
  printf "  ${C_BOLD}%-16s${C_RESET} %s\n" "Deploy"  "$(if $FLAG_SYMLINK; then echo 'symlinks'; else echo 'copies'; fi)"
  printf "  ${C_BOLD}%-16s${C_RESET} %s\n" "Log"     "$(_sf changes.log)"
  echo ""
  echo -e "  ${C_BOLD}Next steps:${C_RESET}"
  echo -e "  ${C_DIM}1. Log out and back in (shell + session changes)${C_RESET}"
  echo -e "  ${C_DIM}2. Start niri → check waybar, mako, fuzzel${C_RESET}"
  echo -e "  ${C_DIM}3. $(basename "$0") status — inspect state anytime${C_RESET}"
  echo ""
}

# =============================================================================
#  COMMAND: auto  (default — full install for new users)
# =============================================================================
cmd_auto() {
  section "Auto — bootstrap + install (full setup)"

  ! command -v pacman &>/dev/null && { err "pacman not found. Arch-based distro only."; exit 1; }
  [[ "$EUID" -eq 0 ]]             && { err "Do not run as root. sudo is used internally."; exit 1; }

  echo ""
  echo -e "  ${C_BOLD}This will:${C_RESET}"
  echo -e "  ${C_DIM}1. Install yay (AUR helper) if needed${C_RESET}"
  echo -e "  ${C_DIM}2. Install all required packages${C_RESET}"
  echo -e "  ${C_DIM}3. Set fish as default shell${C_RESET}"
  echo -e "  ${C_DIM}4. Deploy all configs, themes, fonts and wallpapers${C_RESET}"
  echo ""

  confirm "Proceed with full setup?" || { info "Aborted."; exit 0; }

  # Bootstrap (skip se já feito) — erros não-críticos não param o install
  cmd_bootstrap || warn "Bootstrap terminou com avisos — continuando com install..."

  # Install com packages
  FLAG_INSTALL_PKGS=true
  cmd_install
}

# =============================================================================
#  COMMAND: update
# =============================================================================
cmd_update() {
  section "Update — profile: $PROFILE"
  FLAG_FORCE=true
  run_deploy
  echo ""; ok "Update complete."; echo ""
}

# =============================================================================
#  ENTRYPOINT
# =============================================================================
state::init

[[ "$COMMAND" == "bootstrap" && "$EUID" -eq 0 ]] && { err "Do not run as root."; exit 1; }

case "$COMMAND" in
  auto)      cmd_auto ;;
  bootstrap) cmd_bootstrap ;;
  install)   cmd_install ;;
  update)    cmd_update ;;
  rollback)  cmd_rollback ;;
  status)    cmd_status ;;
  *)         err "Unknown command: $COMMAND"; usage ;;
esac
