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
- [2026-04-01 12:00] `uname -a && bash --version && git --version && ls -R` -> Gathered system info and project structure.
- [2026-04-01 12:01] `read_file GOAL.md` & `read_file README.md` -> Understood project goals and features.
- [2026-04-01 12:05] `read_file setup.sh` -> Analyzed current implementation of the bootstrap script.
- [2026-04-01 12:15] `sed`, `grep`, `replace` -> Modified `setup.sh` to add `yazi` and `gitconfig` modules, and improve idempotency.
- [2026-04-01 12:20] `./setup.sh --all --dry-run` -> Validated the script and fixed syntax errors.
- [2026-04-01 12:40] `replace` -> Added `--list` and `list` options to `setup.sh`.
- [2026-04-01 12:41] `./setup.sh --list` & `./setup.sh list` -> Verified the module lister works.
- [2026-04-01 13:00] `replace` -> Added centralized dependencies (Task 1).
- [2026-04-01 13:05] `replace` -> Added robust logging and error trap (Task 2).
- [2026-04-01 13:10] `replace` -> Added state tracking and deep idempotency version checks (Tasks 3 and 4).
- [2026-04-01 13:20] `replace` -> Added post-install hook UX polish (Task 5) and security/configurability overrides (Task 6).
- [2026-04-01 13:25] `./setup.sh --all --dry-run` -> Validated all senior sysops improvements successfully.

## 5. Test Runs
- [2026-04-01 12:20] `./setup.sh --all --dry-run` -> **PASS**.
- [2026-04-01 12:41] `./setup.sh --list` -> **PASS**. Output: `nvim, zsh, starship, alacritty, tmux, yazi, gitconfig`.
- [2026-04-01 13:25] `./setup.sh --all --dry-run` -> **PASS**. Logged correctly to `~/.local/share/bootstrap/setup.log`, extracted versions, updated state safely in dry-run mode, and showed final UX hook.

## 6. Key Decisions & Architecture Notes
- **Modular Design:** Each tool is its own module.
- **Abstraction:** Package manager commands abstracted.
- **Idempotency:** Implemented deep version checks and a state layer (`~/.local/share/bootstrap/state`). Tool skips install if version matches or already present.
- **Dry-Run Wrapper:** `execute()` function wraps commands and state sets natively.
- **Module Lister:** Added a dedicated `list_modules` function for discoverability.
- **Dependencies:** Centralized `install_base_dependencies` and `install_build_dependencies` to avoid duplicated `PKG_INSTALL` commands.
- **Error Trapping:** `exec > >(tee -a log) 2>&1` + `trap ERR` implemented.

## 7. Issues & Resolutions
- **Issue:** Dependency duplication across modules. **Resolution:** Created centralized base and build dependency layers.
- **Issue:** Idempotency lacked depth (e.g. version checking). **Resolution:** Added `get_tool_version` regex check to fetch tool versions, paired with `set_state` state persistence.
- **Issue:** No persistent logging. **Resolution:** Redirected execution stdout/stderr to tee with a setup log file.
- **Issue:** Curl scripts present risk. **Resolution:** Added info warning on `starship` module regarding curl pipe execution.

## 8. Current Status & Next Steps
- [x] Initial research and project understanding.
- [x] Creation of `MEMORY.md`.
- [x] Analysis of `setup.sh`.
- [x] Implement `yazi` module.
- [x] Improve idempotency for `nvim`, `starship`, and `alacritty`.
- [x] Add `git config` module.
- [x] Update `ALL_MODULES` and main loop for new modules.
- [x] Add `--list` / `list` option.
- [x] Centralize dependency layer.
- [x] Add logging and error trap.
- [x] State tracking and version checks.
- [x] Post-install UX hook.
- [x] Overridable configuration environments.
- [ ] Bonus: Profile flags (`--profile`).
- [ ] Bonus: Status command (`--status`).
- [ ] Bonus: Self-update.
