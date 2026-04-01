🚀 GOAL.md — Universal Linux Bootstrap Environment
🎯 Objective

Create a single, reliable, idempotent installation script that bootstraps a fresh Linux system into a fully configured development environment using:

Personal dotfiles (~/.dotfiles)
Preferred tools (nvim, tmux, zsh, starship, alacritty, etc.)
Cross-distro compatibility (Debian-based, Arch, Fedora)

The script must be:

Portable → works across multiple Linux distributions
Deterministic → same result every time
Idempotent → safe to re-run without breaking the system
Modular → install only what is needed
Extensible → easy to add new tools
🧠 Philosophy

This project is not just a script — it's a personal environment compiler.

Instead of manually setting up systems repeatedly, the goal is to:

Describe the desired system state → let the script reproduce it anywhere.

🧱 Core Components
1. Dotfiles Management
Source of truth:
👉 https://github.com/Tatarotus/dotfiles
Managed using GNU Stow
Structure:
nvim/
zsh/
tmux/
starship/
alacritty/
yazi/

✅ Requirements:

Clone if missing
Pull if already exists
Stow per-module (not globally)
2. Package Management Abstraction

The script must detect OS and adapt:

Distro Type	Manager
Debian/Ubuntu	nala
Arch	pacman
Fedora	dnf

✅ Requirements:

Install nala automatically if missing
Abstract install/update commands
Never hardcode apt
3. Modular Installation System

Each tool must be its own module:

Example:

module_nvim
module_zsh
module_tmux
module_starship
module_alacritty

✅ Requirements:

Install via --all or --install nvim,zsh
Each module:
Installs dependencies
Installs the program
Applies dotfiles via stow
4. Idempotency Guarantees

The script must:

Avoid reinstalling already installed tools unnecessarily
Avoid duplicating configs
Avoid failing if rerun

Examples:

Check before cloning repo
Check before changing shell
Use safe package manager flags
5. Dry-Run System

Support:

./setup.sh --all --dry-run

✅ Requirements:

Show all actions without executing
Wrap all state-changing commands
6. Architecture Awareness

Support:

x86_64
aarch64

✅ Required for:

Binary downloads
Future tool installations
7. Developer Experience

The script should feel like a tool, not just a script.

Include:

Colored logs (INFO, WARN, ERROR, SUCCESS)
Verbose mode
Clear output for each step
🔧 Current State (What Exists)

✅ OS detection
✅ Package manager abstraction
✅ Modular system
✅ Dry-run support
✅ Neovim built from source
✅ Dotfiles cloning + stow
✅ Zsh shell switching

⚠️ Gaps / Improvements Needed

These are next tasks for the junior dev:

🔹 1. Add Missing Modules
yazi (already in dotfiles, not installed)
git config module (optional but valuable)
🔹 2. Improve Idempotency

Examples to fix:

Detect if Neovim is already installed (avoid rebuild every run)
Detect if Starship is already installed
Avoid reinstalling dependencies repeatedly
🔹 3. Standardize Installation Strategy

Right now it's inconsistent:

nvim → source build ✅
alacritty → sometimes cargo ⚠️
starship → curl script ⚠️

👉 Define rules:

Tool	Strategy
nvim	source build
starship	official script
alacritty	pkg manager → fallback cargo
tmux	pkg manager
🔹 4. Add Dependency Layer

Split:

system dependencies
app installation

This avoids duplication across modules.

🔹 5. Add Logging to File

Example:

~/.local/share/setup.log
🔹 6. Add Rollback Awareness (Optional Advanced)

If something fails:

show where
suggest recovery
🔹 7. Add Post-Install Hooks

Examples:

Set default shell after all installs
Reload environment
Print next steps
🧪 Testing Strategy

Before merging anything:

Test Matrix
OS	Test
Ubuntu	✅
Arch	✅
Fedora	✅
Scenarios
Fresh system
Re-run script (idempotency)
Partial install (--install nvim)
Dry run
🧑‍💻 Instructions for Junior Dev

When adding a new tool:

Create a new module:

module_<tool>()

Add to:

ALL_MODULES=(...)
Ensure:
Dependencies installed
Tool installed
stow_module <tool> called
Respect:
DRY_RUN
OS differences
Idempotency

Test:

./setup.sh --install <tool> --dry-run
./setup.sh --install <tool>
also include ./setup.sh --list or ./setup.sh list to list all available modules

🔮 Future Vision
Turn this into a full environment bootstrap framework
Add:
Docker / devcontainers support
Remote server bootstrap (SSH)
Workstation vs minimal profiles
Plugin system
🏁 End Goal

Run one command on any machine:

./setup.sh --all

And get:

Fully configured shell (zsh + starship)
Editor (nvim)
Terminal (alacritty)
Workflow (tmux)
File manager (yazi)
Personal configs applied automatically
