# Project Memory

## 1. Project Overview
**Name:** Universal Linux Bootstrap Environment
**Objective:** Create a single, reliable, idempotent installation script that bootstraps a fresh Linux system into a fully configured development environment using personal dotfiles, preferred tools (nvim, tmux, zsh, starship, alacritty, etc.), and cross-distro compatibility (Debian-based, Arch, Fedora).
**Tech Stack:** Bash script, GNU Stow, git, various CLI tools (nvim, tmux, zsh, etc.).
**Current Status:**
- OS detection and package manager abstraction implemented.
- Modular system with dry-run support.
- Neovim built from source.
- Dotfiles cloning + stow implemented.
- Zsh shell switching implemented.
- **Gaps:** Need to add `yazi` and `git config` modules, improve idempotency (avoid rebuilding/reinstalling if already present), standardize installation strategies, and add a dependency layer.

## 2. Environment & Setup
- **OS:** Linux spark 6.17.0-19-generic #19~24.04.2-Ubuntu SMP PREEMPT_DYNAMIC Fri Mar  6 23:08:46 UTC 2 x86_64 x86_64 x86_64 GNU/Linux (Ubuntu 24.04.2)
- **Bash Version:** 5.2.21(1)-release (x86_64-pc-linux-gnu)
- **Git Version:** 2.43.0
- **Tools:** `nala`, `pacman`, `dnf` abstractions expected in script.

## 3. Project Structure
```
.
├── GEMINI.md
├── GOAL.md
├── README.md
├── setup.sh
└── TODO.md
```

## 4. Commands Executed
- [2026-04-01 12:00] `uname -a && bash --version && git --version && ls -R` -> Gathered system info.
- [2026-04-01 12:01] `read_file GOAL.md` & `read_file README.md` -> Understood project goals.
- [2026-04-01 12:05] `read_file setup.sh` -> Analyzed current implementation.
- [2026-04-01 13:25] Senior SysOps refactor (Tasks 1-6) -> Hardened state, versioning, and logging.
- [2026-04-01 18:40] `replace` -> Added `--list`, categorized drift, and fixed pre-release versioning logic.
- [2026-04-01 19:54] `replace` -> Added retry logic and `apt-get` fallback for robust package management.
- [2026-04-01 20:30] `replace` -> Added `node`, `aliases`, `zoxide`, and `eza` modules.
- [2026-04-01 21:15] `replace` -> Added `fonts` (JetBrainsMono Nerd Font) and `auto-enter-zsh`.
- [2026-04-01 22:00] `write_file` -> Structural overhaul to fix "execute not found" and `SUDO_USER` pathing.

## 5. Test Runs
- [2026-04-01 12:20] `./setup.sh --all --dry-run` -> **PASS**.
- [2026-04-01 13:25] `./setup.sh --all --dry-run` (Senior Refactor) -> **PASS**.
- [2026-04-01 21:40] Docker validation (Arch, Ubuntu, Fedora) -> **PASS** (with gitconfig stow warning).

## 6. Key Decisions & Architecture Notes
- **Source of Truth:** The actual system is the primary source of truth; the state file acts as a cache/record of intent.
- **Permission Handling:** Implemented `REAL_USER` and `REAL_HOME` logic to ensure personal configurations (dotfiles, aliases, fonts) are correctly mapped even when run with `sudo`.
- **Atomicity (Reasoning):** Discussed "Stage and Swap" pattern for future production hardening.
- **Reproducibility:** Shifted to a Manifest-centric architecture (conditional logic per distro).

## 7. Issues & Resolutions
- **Issue:** "execute: command not found". **Resolution:** Moved helper function definitions to the top of the script.
- **Issue:** Permission denied on `.local/share`. **Resolution:** Forced `chown` to `REAL_USER` after directory creation.
- **Issue:** Git pull failure with unstaged changes. **Resolution:** Added `--rebase --autostash` to `module_dotfiles`.

## 8. Current Status & Next Steps
- [x] Hardened version semantics.
- [x] Explicit drift categorization.
- [x] Quiet Git idempotency.
- [x] `SUDO_USER` awareness.
- [x] Nerd Font installation.
- [x] Node.js and improved aliases.
- [ ] Implement Functional Verifiers (Smoke Tests).
- [ ] YAML Manifest for environment pinning.
