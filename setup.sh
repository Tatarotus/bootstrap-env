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

VERIFY_MODE=0
MODULES_TO_VERIFY=()
VERIFY_PASS_COUNT=0
VERIFY_FAIL_COUNT=0

# Task: Handle REAL_USER and REAL_HOME even if run with sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

DOTFILES_DIR="${DOTFILES_DIR:-$REAL_HOME/.dotfiles}"
MODULES_TO_INSTALL=()
ALL_MODULES=("nvim" "zsh" "starship" "alacritty" "tmux" "yazi" "gitconfig" "node" "aliases" "fonts")

# Ensure /usr/local/bin is in PATH for the script's duration
export PATH="/usr/local/bin:$PATH"

# Required minimum versions for critical tools
declare -A MIN_VERSIONS=(
    [nvim]="0.10.0"
    [tmux]="3.3"
    [starship]="1.0.0"
    [zsh]="5.8"
)

# --- UI Helpers ---
info() { echo -e "\e[34m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }
success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }
error_no_exit() { echo -e "\e[31m[ERROR]\e[0m $*"; }

# --- Logic Helpers ---
validate_modules() {
    local -n mods=$1
    local valid_mods=" ${ALL_MODULES[*]} "
    for mod in "${mods[@]}"; do
        if [[ ! "$valid_mods" =~ " $mod " ]]; then
            error "Unknown module: $mod"
        fi
    done
}

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

version_ge() {
    local v_sys=$1
    local v_req=$2
    [[ "$v_sys" == "$v_req" ]] && return 0
    if [[ "$v_sys" == *[-+]* ]] && [[ "$v_req" != *[-+]* ]]; then
        local v_sys_base="${v_sys%%[-+]*}"
        if [[ "$v_sys_base" == "$v_req" ]]; then
            return 1 
        fi
    fi
    [[ "$(printf '%s\n%s' "$v_sys" "$v_req" | sort -V | head -n1)" == "$v_req" ]]
}

# --- State & Logging Path Setup ---
STATE_DIR="$REAL_HOME/.local/share/bootstrap"
STATE_FILE="$STATE_DIR/state"
LOG_FILE="$STATE_DIR/setup.log"

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
            if [[ $# -eq 1 ]]; then
                eval "$1" || exit_code=$?
            else
                "$@" || exit_code=$?
            fi

            if [[ $exit_code -eq 0 ]]; then
                success=1
                hash -r 2>/dev/null || true
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

set_state() {
    local module=$1
    local value=$2
    [[ "$DRY_RUN" -eq 1 ]] && { info "[DRY-RUN] State: $module=$value"; return; }
    execute mkdir -p "$STATE_DIR"
    execute chown -R "$REAL_USER:$REAL_USER" "$STATE_DIR" 2>/dev/null || true
    touch "$STATE_FILE"
    (grep -v "^$module=" "$STATE_FILE" 2>/dev/null || true; echo "$module=$value") | sort -u > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    execute chown "$REAL_USER:$REAL_USER" "$STATE_FILE" 2>/dev/null || true
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
            execute $PKG_INSTALL git curl stow unzip jq fd-find ripgrep fzf zoxide eza fontconfig
            ;;
        arch|manjaro)
            execute $PKG_INSTALL git curl stow unzip jq fd ripgrep fzf zoxide eza fontconfig
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
    info "Stowing $1 for $REAL_USER..."
    if [[ -d "$DOTFILES_DIR/$1" ]]; then
        (cd "$DOTFILES_DIR" && execute stow -R "$1")
    else
        warn "Module directory $DOTFILES_DIR/$1 missing. Skipping stow for $1."
    fi
}

# --- Module: Dotfiles ---
module_dotfiles() {
    info "Setting up Dotfiles for $REAL_USER..."
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        execute git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
        execute chown -R "$REAL_USER:$REAL_USER" "$DOTFILES_DIR"
    elif [[ -d "$DOTFILES_DIR/.git" ]]; then
        info "Dotfiles already cloned at $DOTFILES_DIR. Pulling latest (autostash enabled)..."
        (cd "$DOTFILES_DIR" && execute git pull --rebase --autostash)
    else
        warn "$DOTFILES_DIR exists but is not a git repository. Skipping pull."
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
    local zsh_path=$(command -v zsh || echo "/usr/bin/zsh")
    [[ "$(getent passwd "$REAL_USER" | cut -d: -f7)" != "$zsh_path" ]] && \
        execute $sudo_cmd chsh -s "$zsh_path" "$REAL_USER"
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

git_config_set() {
    local key=$1
    local value=$2
    local current
    if [[ "$EUID" -eq 0 ]]; then
        current=$(sudo -u "$REAL_USER" git config --global "$key" || echo "")
        if [[ "$current" != "$value" ]]; then
            execute sudo -u "$REAL_USER" git config --global "$key" "$value"
        fi
    else
        current=$(git config --global "$key" || echo "")
        if [[ "$current" != "$value" ]]; then
            execute git config --global "$key" "$value"
        fi
    fi
}

module_gitconfig() {
    info "Configuring Git for $REAL_USER..."
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
    info "Configuring personal aliases for $REAL_USER..."
    local zshrc="$REAL_HOME/.zshrc"
    [[ ! -f "$zshrc" ]] && execute touch "$zshrc" && execute chown "$REAL_USER:$REAL_USER" "$zshrc"
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
        if ! grep -q "alias $key=" "$zshrc" 2>/dev/null; then
            echo "alias $key='$val'" >> "$zshrc"
            info "Added alias: $key"
        fi
    done
    if ! grep -q "zoxide init zsh" "$zshrc" 2>/dev/null; then
        echo 'eval "$(zoxide init zsh)"' >> "$zshrc"
        info "Initialized zoxide in $zshrc"
    fi
    set_state "aliases" "configured"
}

module_fonts() {
    info "Installing JetBrainsMono Nerd Font for $REAL_USER..."
    local font_dir="$REAL_HOME/.local/share/fonts"
    execute mkdir -p "$font_dir"
    execute chown -R "$REAL_USER:$REAL_USER" "$(dirname "$font_dir")" 2>/dev/null || true
    if ls "$font_dir"/JetBrainsMono* &>/dev/null; then
        info "JetBrainsMono Nerd Font already installed."
        set_state "fonts" "installed"
        return
    fi
    local temp_dir="/tmp/fonts_build"
    execute rm -rf "$temp_dir"
    execute mkdir -p "$temp_dir"
    execute curl -fLo "$temp_dir/JetBrainsMono.zip" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    execute unzip -o "$temp_dir/JetBrainsMono.zip" -d "$font_dir"
    execute chown -R "$REAL_USER:$REAL_USER" "$font_dir"
    execute fc-cache -f
    execute rm -rf "$temp_dir"
    set_state "fonts" "installed"
}

# --- Verification Helpers ---
record_verify_result() {
    local module=$1
    local status=$2
    local message=$3
    if [[ "$status" == "pass" ]]; then
        success "$module: $message"
        VERIFY_PASS_COUNT=$((VERIFY_PASS_COUNT + 1))
    else
        error_no_exit "$module: $message"
        VERIFY_FAIL_COUNT=$((VERIFY_FAIL_COUNT + 1))
    fi
}

verify_tool_exists() {
    local cmd=$1
    if command -v "$cmd" &>/dev/null; then
        return 0
    fi
    return 1
}

verify_tool_min_version() {
    local cmd=$1
    local required=$2
    local current=$(get_tool_version "$cmd")
    if [[ "$current" == "none" ]]; then
        return 1
    fi
    if version_ge "$current" "$required"; then
        return 0
    fi
    return 1
}

verify_dotfiles_module_present() {
    local module=$1
    if [[ -d "$DOTFILES_DIR/$module" ]]; then
        return 0
    fi
    return 1
}

verify_git_config() {
    local key=$1
    local expected=$2
    local current
    if [[ "$EUID" -eq 0 ]]; then
        current=$(sudo -u "$REAL_USER" git config --global "$key" || echo "")
    else
        current=$(git config --global "$key" || echo "")
    fi
    if [[ "$current" == "$expected" ]]; then
        return 0
    fi
    return 1
}

# --- Verifiers ---
verify_nvim() {
    local errors=()
    if ! verify_tool_exists nvim; then
        errors+=("executable missing")
    else
        if ! verify_tool_min_version nvim "${MIN_VERSIONS[nvim]}"; then
            errors+=("version $(get_tool_version nvim) < ${MIN_VERSIONS[nvim]}")
        fi
    fi
    if ! verify_dotfiles_module_present nvim; then
        errors+=("dotfiles module missing")
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "nvim" "pass" "executable present, version ok, dotfiles present"
    else
        record_verify_result "nvim" "fail" "${errors[*]}"
    fi
}

verify_zsh() {
    local errors=()
    if ! verify_tool_exists zsh; then
        errors+=("executable missing")
    else
        local zsh_path=$(command -v zsh)
        local login_shell=$(getent passwd "$REAL_USER" | cut -d: -f7)
        if [[ "$login_shell" != "$zsh_path" ]]; then
            errors+=("login shell is $login_shell instead of $zsh_path")
        fi
    fi
    if ! verify_dotfiles_module_present zsh; then
        errors+=("dotfiles module missing")
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "zsh" "pass" "executable present, login shell ok, dotfiles present"
    else
        record_verify_result "zsh" "fail" "${errors[*]}"
    fi
}

verify_starship() {
    local errors=()
    if ! verify_tool_exists starship; then
        errors+=("executable missing")
    else
        if ! verify_tool_min_version starship "${MIN_VERSIONS[starship]}"; then
            errors+=("version $(get_tool_version starship) < ${MIN_VERSIONS[starship]}")
        fi
    fi
    if ! verify_dotfiles_module_present starship; then
        errors+=("dotfiles module missing")
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "starship" "pass" "executable present, version ok, dotfiles present"
    else
        record_verify_result "starship" "fail" "${errors[*]}"
    fi
}

verify_alacritty() {
    local errors=()
    if ! verify_tool_exists alacritty; then
        errors+=("executable missing")
    else
        if ! alacritty --version &>/dev/null && ! alacritty --help &>/dev/null; then
            errors+=("does not respond to version/help")
        fi
    fi
    if ! verify_dotfiles_module_present alacritty; then
        errors+=("dotfiles module missing")
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "alacritty" "pass" "executable present, responds to commands, dotfiles present"
    else
        record_verify_result "alacritty" "fail" "${errors[*]}"
    fi
}

verify_tmux() {
    local errors=()
    if ! verify_tool_exists tmux; then
        errors+=("executable missing")
    else
        if ! verify_tool_min_version tmux "${MIN_VERSIONS[tmux]}"; then
            errors+=("version $(get_tool_version tmux) < ${MIN_VERSIONS[tmux]}")
        fi
        local session_name="verify_test_$$"
        if tmux new-session -d -s "$session_name" 2>/dev/null; then
            tmux kill-session -t "$session_name" 2>/dev/null
        else
            errors+=("failed to create detached session")
        fi
    fi
    if ! verify_dotfiles_module_present tmux; then
        errors+=("dotfiles module missing")
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "tmux" "pass" "executable present, version ok, session test passed, dotfiles present"
    else
        record_verify_result "tmux" "fail" "${errors[*]}"
    fi
}

verify_yazi() {
    local errors=()
    if ! verify_tool_exists yazi; then
        errors+=("executable missing")
    else
        if ! yazi --version &>/dev/null && ! yazi --help &>/dev/null; then
            errors+=("does not respond to version/help")
        fi
    fi
    if ! verify_dotfiles_module_present yazi; then
        errors+=("dotfiles module missing")
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "yazi" "pass" "executable present, responds to commands, dotfiles present"
    else
        record_verify_result "yazi" "fail" "${errors[*]}"
    fi
}

verify_gitconfig() {
    local errors=()
    if ! verify_git_config "init.defaultBranch" "main"; then
        errors+=("init.defaultBranch mismatch")
    fi
    if ! verify_git_config "pull.rebase" "true"; then
        errors+=("pull.rebase mismatch")
    fi
    if ! verify_git_config "core.editor" "nvim"; then
        errors+=("core.editor mismatch")
    fi
    if ! verify_dotfiles_module_present gitconfig; then
        errors+=("dotfiles module missing")
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "gitconfig" "pass" "git configuration matches expected values, dotfiles present"
    else
        record_verify_result "gitconfig" "fail" "${errors[*]}"
    fi
}

verify_node() {
    local errors=()
    if ! verify_tool_exists node; then
        errors+=("executable missing")
    else
        local ver=$(node --version 2>/dev/null)
        if [[ -z "$ver" ]]; then
            errors+=("failed to get version string")
        fi
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "node" "pass" "executable present, version ok"
    else
        record_verify_result "node" "fail" "${errors[*]}"
    fi
}

verify_aliases() {
    local errors=()
    local zshrc="$REAL_HOME/.zshrc"
    if [[ ! -f "$zshrc" ]]; then
        errors+=("$zshrc missing")
    else
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
            if ! grep -Fq "alias $key='$val'" "$zshrc" 2>/dev/null; then
                errors+=("alias $key missing or mismatched")
            fi
        done
        if ! grep -q "zoxide init zsh" "$zshrc" 2>/dev/null; then
            errors+=("zoxide init zsh missing")
        fi
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "aliases" "pass" "expected aliases and init scripts present"
    else
        record_verify_result "aliases" "fail" "${errors[*]}"
    fi
}

verify_fonts() {
    local errors=()
    local font_dir="$REAL_HOME/.local/share/fonts"
    if ! ls "$font_dir"/JetBrainsMono* &>/dev/null; then
        errors+=("JetBrainsMono files missing in $font_dir")
    fi
    if verify_tool_exists fc-list; then
        if ! fc-list | grep -iq "JetBrainsMono"; then
            errors+=("fc-list cannot resolve JetBrainsMono")
        fi
    fi
    if [[ ${#errors[@]} -eq 0 ]]; then
        record_verify_result "fonts" "pass" "font files present and discoverable"
    else
        record_verify_result "fonts" "fail" "${errors[*]}"
    fi
}

status() {
    echo -e "\n\e[34m[SYSTEM STATUS]\e[0m"
    for mod in "${ALL_MODULES[@]}"; do
        local current=$(get_tool_version "$mod")
        local required="${MIN_VERSIONS[$mod]}"
        local state_val=$(grep "^$mod=" "$STATE_FILE" 2>/dev/null | cut -d= -f2)
        if [[ "$mod" == "gitconfig" || "$mod" == "aliases" || "$mod" == "fonts" ]]; then
            [[ "$state_val" == "configured" || "$state_val" == "installed" ]] && \
                echo -e "  $mod: $state_val \e[32m✓\e[0m" || echo -e "  $mod: \e[31mmissing ✗\e[0m"
            continue
        fi
        local drift=""
        if [[ -n "$state_val" ]] && [[ "$state_val" != "$current" ]]; then
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

usage() {
    cat << EOF
$(info "Bootstrap Environment Compiler")
Role: Master Bash Scripter & Linux Environment Architect
Usage: $0 [options]
$(info "Core Commands:")
  --all, --install [mods], --verify [mods], --status, status, --list, list
$(info "Engine Flags:")
  --dry-run, --verbose, --help
$(info "Available Modules:")
  $(echo "${ALL_MODULES[@]}" | sed 's/ /, /g')
$(info "Documentation:")
  Logs: $LOG_FILE | State: $STATE_FILE
EOF
    exit 0
}

parse_args() {
    [[ $# -eq 0 ]] && usage
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) MODULES_TO_INSTALL=("${ALL_MODULES[@]}"); shift ;;
            --install) IFS=',' read -ra ADDR <<< "$2"; MODULES_TO_INSTALL+=("${ADDR[@]}"); shift 2 ;;
            --verify)
                VERIFY_MODE=1
                if [[ -n "$2" && "$2" != --* ]]; then
                    IFS=',' read -ra ADDR <<< "$2"
                    MODULES_TO_VERIFY+=("${ADDR[@]}")
                    shift 2
                else
                    MODULES_TO_VERIFY=("${ALL_MODULES[@]}")
                    shift
                fi
                ;;
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
    
    if [[ "$VERIFY_MODE" -eq 1 ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            warn "Dry-run is ignored in verification mode. Real checks will be performed."
        fi
        validate_modules MODULES_TO_VERIFY
        info "Running verification for modules: ${MODULES_TO_VERIFY[*]}"
        for mod in "${MODULES_TO_VERIFY[@]}"; do
            case "$mod" in
                nvim) verify_nvim ;;
                zsh) verify_zsh ;;
                starship) verify_starship ;;
                alacritty) verify_alacritty ;;
                tmux) verify_tmux ;;
                yazi) verify_yazi ;;
                gitconfig) verify_gitconfig ;;
                node) verify_node ;;
                aliases) verify_aliases ;;
                fonts) verify_fonts ;;
            esac
        done
        
        echo -e "\n\e[34m[VERIFICATION SUMMARY]\e[0m"
        echo -e "  Passed: \e[32m$VERIFY_PASS_COUNT\e[0m"
        echo -e "  Failed: \e[31m$VERIFY_FAIL_COUNT\e[0m"
        
        if [[ $VERIFY_FAIL_COUNT -gt 0 ]]; then
            exit 1
        else
            exit 0
        fi
    fi

    detect_os
    setup_package_manager
    validate_modules MODULES_TO_INSTALL
    
    execute mkdir -p "$STATE_DIR"
    execute chown -R "$REAL_USER:$REAL_USER" "$STATE_DIR" 2>/dev/null || true
    exec > >(while read -r line; do echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"; done | tee -a "$LOG_FILE") 2>&1
    trap 'error "Failed at line $LINENO – check $LOG_FILE"' ERR

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
            fonts) module_fonts ;;
        esac
    done
    success "Setup complete! Summary:"
    [[ -f "$STATE_FILE" ]] && sed 's/^/  ✓ /' "$STATE_FILE"
    if [[ "$DRY_RUN" -eq 0 ]] && command -v zsh &>/dev/null; then
        info "Switching to Zsh session..."
        if [[ "$EUID" -eq 0 ]]; then
            exec sudo -u "$REAL_USER" zsh -l
        else
            exec zsh -l
        fi
    fi
}

main "$@"