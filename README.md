# Dotfiles & Environment Setup

A modular, architecture-aware bash script to bootstrap my Linux environment. This script installs dependencies, builds core tools from source, and symlinks configurations using GNU Stow.

## Features
* **Modular Installation:** Choose exactly what to install or install everything at once.
* **Architecture Aware:** Supports `x86_64` and `aarch64`.
* **Cross-Distribution:** Supports Ubuntu, Linux Mint, Debian, Arch Linux, Fedora, and NixOS.
* **Dry Run Mode:** See exactly what commands will be executed without modifying your system.
* **GNU Stow:** Clean, symlink-based dotfile management.

## Supported Applications
* **Neovim** (Built from latest stable source)
* **Zsh** (Set as default shell)
* **Starship** (Prompt framework)
* **Alacritty** (Terminal emulator)
* **Tmux** (Terminal multiplexer)

## Usage

Clone the repository to your home directory:
\`\`\`bash
git clone https://github.com/Tatarotus/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
\`\`\`

Run the setup script:
\`\`\`bash
# See available options
./setup.sh --help

# Preview changes without applying them
./setup.sh --all --dry-run

# Install everything
./setup.sh --all

# Install only specific components
./setup.sh --install nvim,zsh,starship
\`\`\`
