# Project TODOs

## Phase 1: Core Script Refactoring
- [x] Remove `gh` dependency and replace with standard `git clone`.
- [x] Implement a robust argument parser (support `--all`, `--install <list>`, `--dry-run`, `--help`).
- [x] Implement OS detection and package manager abstraction (nala, pacman, dnf, nix-env).
- [x] Implement architecture detection (`x86_64` vs `aarch64`).

## Phase 2: Application Modules
- [x] **Neovim:** Write source-build logic.
- [x] **Zsh:** Write install logic and shell switching.
- [x] **Starship:** Write install logic.
- [x] **Alacritty:** Write install/build logic.
- [x] **Tmux:** Write install logic.
- [x] **Yazi:** Write install logic.
- [x] **Node.js:** Support for nvim plugins.
- [x] **Fonts:** JetBrainsMono Nerd Font.
- [x] **Aliases:** Enhanced aliases with eza and zoxide.

## Phase 3: Polish
- [x] Verify idempotency.
- [x] Verify `--dry-run`.
- [x] Test on Arch Linux container.
- [x] Test on Debian/Ubuntu container.
- [x] Test on Fedora container.
- [x] Explicit drift detection in `--status`.
- [x] `SUDO_USER` awareness for correct pathing.

 Your Next Tasks (Prioritized – Do in This Order)
 Task 1 – Centralized Dependency Layer (Biggest win) - [x] Done
Create two new functions:install_base_dependencies() → git, curl, stow, etc.
install_build_dependencies() → cmake, ninja, etc. (only when needed)

Then every module just calls the right one(s). Remove all the scattered PKG_INSTALL calls inside modules.

Task 2 – Robust Logging + Error Trap - [x] Done
  bash

LOG_FILE="$HOME/.local/share/bootstrap/setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'error "Failed at line $LINENO – check $LOG_FILE"' ERR

Task 3 – State Tracking - [x] Done
Create:bash

STATE_DIR="$HOME/.local/share/bootstrap"
STATE_FILE="$STATE_DIR/state"

Simple key=value format is fine for now. Track installed modules + versions.

Task 4 – Deep Idempotency + Version Checks - [x] Done
For critical tools (nvim, starship, etc.):Check version (e.g. nvim --version | head -n1)
Add helper: ensure_tool_version "nvim" "0.10+"

Task 5 – Post-Install Hook + UX Polish - [x] Done
At the very end:Print clear “next steps”
Warn if user needs to exec zsh or restart terminal
Show what was actually installed/changed

Task 6 (Nice-to-have but high value) – Security & Configurability - [x] Done
  Replace curl | sh for Starship with a verified download + checksum (or at least document the risk).
Make DOTFILES_REPO and DOTFILES_DIR overridable via environment variables or flags.

Bonus Senior Touches (When You’re Feeling Dangerous)Add --profile minimal|full|workstation
Add setup.sh --status to show current state vs desired state
Make the whole thing self-updating (--self-update)


