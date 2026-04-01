#!/usr/bin/env bash

# ==============================================================================
# Setup Script: Modular, OS-Agnostic, and Architecture-Aware
# Role: Master Bash Scripter & Linux Environment Architect
# ==============================================================================

set -eo pipefail
trap 'exit 1' ERR

# --- Globals & Defaults ---
DRY_RUN=0
VERBOSE=0
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/Tatarotus/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
MODULES_TO_INSTALL=()
ALL_MODULES=("nvim" "zsh" "starship" "alacritty" "tmux" "yazi" "gitconfig" "node" "aliases")

# Ensure /usr/local/bin is in PATH for the script's duration
export PATH="/usr/local/bin:$PATH"

# Required minimum versions for critical tools
declare -A MIN_VERSIONS=(
    [nvim]="0.10.0"
    [tmux]="3.3"
    [starship]="1.0.0"
    [zsh]="5.8"
)

# --- State & Logging ---
STATE_DIR="$HOME/.local/share/bootstrap"
STATE_FILE="$STATE_DIR/state"
LOG_FILE="$STATE_DIR/setup.log"

mkdir -p "$STATE_DIR"
exec > >(while read -r line; do echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"; done | tee -a "$LOG_FILE") 2>&1
trap 'error "Failed at line $LINENO – check $LOG_FILE"' ERR

set_state() {
    local module=$1
    local value=$2
    [[ "$DRY_RUN" -eq 1 ]] && { info "[DRY-RUN] State: $module=$value"; return; }
    touch "$STATE_FILE"
    (grep -v "^$module=" "$STATE_FILE" 2>/dev/null || true; echo "$module=$value") | sort -u > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# --- UI Helpers ---
info() { echo -e "\e[34m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }
success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }

get_tool_version() {
    local cmd=$1
    if ! command -v "$cmd" &>/dev/null; then
        echo "none"
        return
    fi
    local v_output
    v_output=$("$cmd" --version 2>&1 | head -n1)
    echo "$v_output" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.]+)?' | head -n1 || echo "installed"
}

# Task 1: Semantic Version Comparison (Hardened for Pre-releases)
# Edge Case: If both versions have suffixes (e.g. 0.10.0-dev vs 0.10.0-beta), 
# we fall back to lexicographical sort-V. This handles most common cases 
# (beta < rc) without full SemVer parser complexity.
version_ge() {
    local v_sys=$1
    local v_req=$2
    [[ "$v_sys" == "$v_req" ]] && return 0
    
    # If the system version is a pre-release (contains -) but the requirement is stable, 
    # we treat it as lower unless the base numbers are already higher.
    if [[ "$v_sys" == *[-+]* ]] && [[ "$v_req" != *[-+]* ]]; then
        local v_sys_base="${v_sys%%[-+]*}"
        if [[ "$v_sys_base" == "$v_req" ]]; then
            return 1 # 0.10.0-dev < 0.10.0
        fi
    fi
    
    [[ "$(printf '%s\n%s' "$v_sys" "$v_req" | sort -V | head -n1)" == "$v_req" ]]
}

# --- Dry Run Wrapper ---
execute() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo -e "\e[35m[DRY-RUN]\e[0m $*"
    else
        [[ "$VERBOSE" -eq 1 ]] && echo -e "\e[36m[EXEC]\e[0m $*"
        
        local max_retries=2
        local retry_count=0
        local success=0
        
        while [[ $retry_count -le $max_retries ]]; do
            local exit_code=0
            if [[ $# -eq 1 ]] && [[ "$1" == *"|"* ]]; then
                eval "$1" || exit_code=$?
            else
                "$@" || exit_code=$?
            fi

            if [[ $exit_code -eq 0 ]]; then
                success=1
                break
            else
                retry_count=$((retry_count + 1))
                if [[ $retry_count -le $max_retries ]]; then
                    warn "Command failed with exit code $exit_code. Retrying ($retry_count/$max_retries)..."
                    sleep 2
                fi
            fi
        done
        
        if [[ $success -eq 0 ]]; then
            # Special fallback for Ubuntu/Debian if nala is failing
            if [[ "$PKG_MANAGER" == "nala" ]] && [[ "$1" == "$sudo_cmd" ]] && [[ "$2" == "nala" ]]; then
                warn "Nala failed. Falling back to apt-get..."
                local apt_cmd=("${@/nala/apt-get}")
                "${apt_cmd[@]}" || return 1
            else
                return 1
            fi
        fi
    fi
}

# --- System Detection ---
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        LIKE=$ID_LIKE
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        error "Unsupported OS."
    fi
    ARCH=$(uname -m)
    info "Detected OS: $OS, Architecture: $ARCH"
}

# --- Package Manager Abstraction ---
setup_package_manager() {
    sudo_cmd="sudo"
    [[ "$EUID" -eq 0 ]] && sudo_cmd=""
    case "$OS" in
        ubuntu|debian|mint|pop)
            PKG_MANAGER="nala"
            if ! command -v nala &>/dev/null; then
                info "Installing nala..."
                execute $sudo_cmd apt update
                execute $sudo_cmd apt install -y nala
            fi
            PKG_INSTALL="$sudo_cmd nala install -y"
            PKG_UPDATE="$sudo_cmd nala update"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            PKG_INSTALL="$sudo_cmd pacman -S --noconfirm --needed"
            PKG_UPDATE="$sudo_cmd pacman -Sy"
            ;;
        fedora)
            PKG_MANAGER="dnf"
            PKG_INSTALL="$sudo_cmd dnf install -y"
            PKG_UPDATE="$sudo_cmd dnf makecache"
            ;;
        *)
            error "Package manager for $OS not configured."
            ;;
    esac
}

# --- Dependency Management ---
install_base_dependencies() {
    info "Installing base dependencies..."
    case "$OS" in
        ubuntu|debian|mint|pop|fedora)
            execute $PKG_INSTALL git curl stow unzip jq fd-find ripgrep fzf zoxide eza
            ;;
        arch|manjaro)
            execute $PKG_INSTALL git curl stow unzip jq fd ripgrep fzf zoxide eza
            ;;
    esac
}

install_build_dependencies() {
    info "Installing build dependencies..."
    case "$OS" in
        ubuntu|debian|mint|pop)
            execute $PKG_INSTALL ninja-build gettext cmake unzip curl build-essential
            ;;
        arch|manjaro)
            execute $PKG_INSTALL base-devel cmake unzip ninja gettext
            ;;
        fedora)
            execute $PKG_INSTALL ninja-build cmake gcc-c++ gettext unzip make
            ;;
    esac
}

# --- stow_module Helper ---
stow_module() {
    info "Stowing $1..."
    if [[ -d "$DOTFILES_DIR/$1" ]]; then
        (cd "$DOTFILES_DIR" && execute stow -R "$1")
    else
        warn "Module directory $DOTFILES_DIR/$1 missing. Skipping stow for $1."
    fi
}

# --- Module: Dotfiles ---
module_dotfiles() {
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        execute git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    else
        (cd "$DOTFILES_DIR" && execute git pull)
    fi
    command -v stow &>/dev/null || execute $PKG_INSTALL stow
}

# --- Modules ---
module_nvim() {
    local current=$(get_tool_version nvim)
    local required="${MIN_VERSIONS[nvim]}"
    if [[ "$current" != "none" ]] && version_ge "$current" "$required"; then
        info "Neovim $current satisfies >= $required. Skipping."
        set_state "nvim" "$current"
        stow_module nvim
        return
    fi
    info "Installing Neovim (Required >= $required)..."
    install_build_dependencies
    local build_dir="/tmp/neovim_build"
    execute rm -rf "$build_dir"
    execute git clone --depth 1 --branch stable https://github.com/neovim/neovim "$build_dir"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        execute "cd $build_dir && make CMAKE_BUILD_TYPE=Release && sudo make install"
    else
        pushd "$build_dir" >/dev/null
        make CMAKE_BUILD_TYPE=Release
        sudo make install
        popd >/dev/null
    fi
    execute rm -rf "$build_dir"
    set_state "nvim" "$(get_tool_version nvim)"
    stow_module nvim
}

module_zsh() {
    local current=$(get_tool_version zsh)
    local required="${MIN_VERSIONS[zsh]}"
    if [[ "$current" == "none" ]] || ! version_ge "$current" "$required"; then
        execute $PKG_INSTALL zsh
        current=$(get_tool_version zsh)
    fi
    set_state "zsh" "$current"
    local current_user="${USER:-$(whoami)}"
    local zsh_path=$(command -v zsh || echo "/usr/bin/zsh")
    [[ "$(getent passwd "$current_user" | cut -d: -f7)" != "$zsh_path" ]] && \
        execute $sudo_cmd chsh -s "$zsh_path" "$current_user"
    stow_module zsh
}

module_starship() {
    local current=$(get_tool_version starship)
    local required="${MIN_VERSIONS[starship]}"
    if [[ "$current" == "none" ]] || ! version_ge "$current" "$required"; then
        execute "curl -sS https://starship.rs/install.sh | sh -s -- -y"
        current=$(get_tool_version starship)
    fi
    set_state "starship" "$current"
    stow_module starship
}

module_alacritty() {
    if ! command -v alacritty &>/dev/null; then
        case "$OS" in
            arch|manjaro) execute $PKG_INSTALL alacritty ;;
            *) command -v cargo &>/dev/null && execute cargo install alacritty || execute $PKG_INSTALL alacritty ;;
        esac
    fi
    set_state "alacritty" "$(get_tool_version alacritty)"
    stow_module alacritty
}

module_tmux() {
    local current=$(get_tool_version tmux)
    local required="${MIN_VERSIONS[tmux]}"
    if [[ "$current" == "none" ]] || ! version_ge "$current" "$required"; then
        execute $PKG_INSTALL tmux
        current=$(get_tool_version tmux)
    fi
    set_state "tmux" "$current"
    stow_module tmux
}

module_yazi() {
    if ! command -v yazi &>/dev/null; then
        case "$OS" in
            ubuntu|debian|mint|pop|fedora) execute $PKG_INSTALL ffmpeg 7zip poppler-utils ;;
            arch|manjaro) execute $PKG_INSTALL ffmpeg 7z poppler ;;
        esac
        case "$OS" in
            arch|manjaro|fedora) execute $PKG_INSTALL yazi ;;
            *) command -v cargo &>/dev/null && execute cargo install --locked yazi-fm yazi-cli ;;
        esac
    fi
    set_state "yazi" "$(get_tool_version yazi)"
    stow_module yazi
}

# Task 3: Quiet Idempotency for Git Configuration
git_config_set() {
    local key=$1
    local value=$2
    local current=$(git config --global "$key" || echo "")
    if [[ "$current" != "$value" ]]; then
        execute git config --global "$key" "$value"
    fi
}

module_gitconfig() {
    info "Configuring Git..."
    git_config_set "init.defaultBranch" "main"
    git_config_set "pull.rebase" "true"
    git_config_set "core.editor" "nvim"
    set_state "gitconfig" "configured"
    stow_module gitconfig
}

module_node() {
    local current=$(get_tool_version node)
    if [[ "$current" != "none" ]]; then
        info "Node.js $current already installed."
        set_state "node" "$current"
        return
    fi

    info "Installing Node.js..."
    case "$OS" in
        ubuntu|debian|mint|pop)
            # Use NodeSource for latest LTS, fallback if it fails
            execute "curl -fsSL https://deb.nodesource.com/setup_lts.x | $sudo_cmd bash -" || warn "NodeSource script failed, falling back to default repo."
            execute $PKG_INSTALL nodejs
            ;;
        arch|manjaro)
            execute $PKG_INSTALL nodejs npm
            ;;
        fedora)
            execute $PKG_INSTALL nodejs
            ;;
    esac
    set_state "node" "$(get_tool_version node)"
}

module_aliases() {
    info "Configuring personal aliases..."
    local zshrc="$HOME/.zshrc"
    
    # Ensure .zshrc exists
    touch "$zshrc"

    declare -A aliases=(
        [ls]="eza --icons"
        [ll]="eza -lah --icons"
        [la]="eza -A --icons"
        [lt]="eza --tree --icons"
        [l]="eza -CF --icons"
        [gs]="git status"
        [ga]="git add"
        [gc]="git commit"
        [gp]="git push"
        [v]="nvim"
        [y]="yazi"
        [z]="z"
    )

    for key in "${!aliases[@]}"; do
        local val="${aliases[$key]}"
        if ! grep -q "alias $key=" "$zshrc"; then
            echo "alias $key='$val'" >> "$zshrc"
            info "Added alias: $key"
        fi
    done

    # Initialize zoxide (z) in zshrc if not present
    if ! grep -q "zoxide init zsh" "$zshrc"; then
        echo 'eval "$(zoxide init zsh)"' >> "$zshrc"
        info "Initialized zoxide in .zshrc"
    fi

    set_state "aliases" "configured"
}

# Task 2: Drift Detection in --status (Signal vs Noise)
status() {
    echo -e "\n\e[34m[SYSTEM STATUS]\e[0m"
    for mod in "${ALL_MODULES[@]}"; do
        local current=$(get_tool_version "$mod")
        local required="${MIN_VERSIONS[$mod]}"
        local state_val=$(grep "^$mod=" "$STATE_FILE" 2>/dev/null | cut -d= -f2)

        if [[ "$mod" == "gitconfig" || "$mod" == "aliases" ]]; then
            if [[ "$state_val" == "configured" ]]; then
                echo -e "  $mod: configured \e[32m✓\e[0m"
            else
                echo -e "  $mod: \e[31mmissing ✗\e[0m"
            fi
            continue
        fi

        local drift=""
        if [[ -n "$state_val" ]] && [[ "$state_val" != "$current" ]]; then
            # Categorize drift
            if [[ "$current" == "none" ]]; then
                drift=" (state=$state_val, system=missing - \e[31mCRITICAL DRIFT\e[0m)"
            elif version_ge "$current" "$state_val"; then
                drift=" (state=$state_val, system=$current - \e[36mnoise: ahead\e[0m)"
            else
                drift=" (state=$state_val, system=$current - \e[33msignal: regressed\e[0m)"
            fi
        fi

        if [[ "$current" == "none" ]]; then
             echo -e "  $mod: \e[31mmissing ✗\e[0m$drift"
        elif [[ -n "$required" ]] && ! version_ge "$current" "$required"; then
             echo -e "  $mod: \e[33moutdated ($current < $required) ⚠\e[0m$drift"
        else
             echo -e "  $mod: installed ($current) \e[32m✓\e[0m$drift"
        fi
    done
    echo ""
    exit 0
}

# --- Usage ---
usage() {
    cat << EOF

$(info "Bootstrap Environment Compiler")
Role: Master Bash Scripter & Linux Environment Architect

Usage: $0 [options]

$(info "Core Commands:")
  --all                Install and configure all modules defined in ALL_MODULES
  --install [mods]     Comma-separated list of specific modules to install
                       Example: $0 --install nvim,tmux,zsh
  --status, status     Inspect the live system, compare against state, and report drift
  --list, list         Display all available modules for installation

$(info "Engine Flags:")
  --dry-run            Show proposed actions without modifying the system
  --verbose            Enable detailed logging of every command executed
  --help               Show this professional help documentation

$(info "Available Modules:")
  $(echo "${ALL_MODULES[@]}" | sed 's/ /, /g')

$(info "Documentation:")
  Logs are persisted at: $LOG_FILE
  State is tracked at:    $STATE_FILE

EOF
    exit 0
}

parse_args() {
    [[ $# -eq 0 ]] && usage
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) MODULES_TO_INSTALL=("${ALL_MODULES[@]}"); shift ;;
            --install) IFS=',' read -ra ADDR <<< "$2"; MODULES_TO_INSTALL+=("${ADDR[@]}"); shift 2 ;;
            --status|status) status ;;
            --list|list) echo "Modules: ${ALL_MODULES[*]}"; exit 0 ;;
            --dry-run) DRY_RUN=1; shift ;;
            --verbose) VERBOSE=1; shift ;;
            --help) usage ;;
            *) error "Unknown argument: $1" ;;
        esac
    done
}

main() {
    parse_args "$@"
    detect_os
    setup_package_manager
    execute $PKG_UPDATE
    install_base_dependencies
    [[ ${#MODULES_TO_INSTALL[@]} -gt 0 ]] && module_dotfiles
    for mod in "${MODULES_TO_INSTALL[@]}"; do
        case "$mod" in
            nvim) module_nvim ;;
            zsh) module_zsh ;;
            starship) module_starship ;;
            alacritty) module_alacritty ;;
            tmux) module_tmux ;;
            yazi) module_yazi ;;
            gitconfig) module_gitconfig ;;
            node) module_node ;;
            aliases) module_aliases ;;
        esac
    done
    success "Setup complete! Summary:"
    [[ -f "$STATE_FILE" ]] && sed 's/^/  ✓ /' "$STATE_FILE"
}

main "$@"
