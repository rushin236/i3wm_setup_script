#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$SCRIPT_DIR/install.log"

# Timestamp format
timestamp() {
	date +"%Y-%m-%d %H:%M:%S"
}

# Logging functions
log_info() {
	echo "$(timestamp) [INFO]    $*"
}

log_success() {
	echo "$(timestamp) [SUCCESS] $*"
}

log_warning() {
	echo "$(timestamp) [WARNING] $*"
}

log_error() {
	echo "$(timestamp) [ERROR]   $*"
}

exec > >(tee -a "$LOGFILE") 2>&1

echo "======================"
echo "=== Script Started ==="
echo "======================"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
x86_64) MACHINE="x86_64" ;;
aarch64) MACHINE="arm64" ;;
armv7l) MACHINE="armv7" ;;
*) log_error "Unsupported arch: $ARCH" && exit 1 ;;
esac
: "$MACHINE"

# Detect distro
if [ -f /etc/arch-release ]; then
	DISTRO="arch"
elif [ -f /etc/debian_version ]; then
	DISTRO="debian"
else
	log_error "Unsupported distro $DISTRO" && exit 1
fi

log_info "Requesting sudo privileges..."

# Ask for sudo up front
if sudo -v; then
	log_success "Sudo privileges granted."
else
	log_error "This script requires sudo privileges. Exiting..."
	exit 1
fi

# i3wm setup packages
declare -A I3_PACKAGES_DESC=(
	[i3wm]="Improved dynamic tiling window manager"
	[polybar]="Fast and easy-to-use status bar"
	[rofi]="Window switcher, run launcher, ssh-launcher and more"
	[dunst]="Lightweight notification daemon"
	[picom]="Standalone compositor for X11"
	[i3lock_color]="Simple lockscreen session locker for i3wm with good themes"
	[betterlockscreen]="Simple lockscreen session locker for i3wm (installed via script)"
	[xrandr]="Interact with the X RandR extension to set screen size/position"
	[autorandr]="Auto-detect and use saved XRandR profiles"
	[dispwin]="Load ICC profiles into the display system (from ArgyllCMS)"
	[wireplumber]="Session and policy manager for PipeWire"
	[libnotify]="Library for sending desktop notifications"
	[policykit]="PolicyKit authentication agent for GNOME/GTK, required for managing system permissions"
	[feh]="Lightweight image viewer and wallpaper setter for X11"
	[dex]="Desktop entry executor for autostarting .desktop files in lightweight environments"
	[networkmanager]="Daemon for managing network connections (wired and wireless)"
	[network_manager_applet]="System tray applet for NetworkManager to manage connections via GUI"
	[xidlehook]="Automatic screen locking daemon after a period of inactivity"
	[easyeffects_fx]="Advanced audio effects and equalizer for PipeWire or PulseAudio"
	[thunar_fe]="A good lightweight file explorer"
	[yazi]="A terminal based file manager"
)
: "${I3_PACKAGES_DESC[@]}"

# Dev tools packages
declare -A DEV_PACKAGES_DESC=(
	[nvim]="Modern Vim-based text editor"
	[alacritty]="GPU-accelerated terminal emulator"
	[tmux]="Terminal multiplexer for managing sessions"
	[zsh]="Powerful interactive shell"
	[fzf]="Tool required for nvim easy fuzzy finding"
	[miniconda]="A mini version of Conda for python"
	[node]="Required for nvim and web dev"
	[rust]="Required for nvim, alacritty install and system programming"
)
: "${DEV_PACKAGES_DESC[@]}"

# ────────────────────────────────────────────────
# Define common and distro-specific packages

# Common packages (same name in both Arch and Debian)
declare -A COMMON_PACKAGES=(
	[i3wm]="i3-wm"
	[polybar]="polybar"
	[rofi]="rofi"
	[dunst]="dunst"
	[picom]="picom"
	[autorandr]="autorandr"
	[wireplumber]="wireplumber"
	[tmux]="tmux"
	[zsh]="zsh"
	[feh]="feh"
	[dex]="dex"
	[policykit]="lxqt-policykit"
	[network_manager_applet]="network-manager-applet"
)

# Arch-specific package names
declare -A ARCH_PACKAGES=(
	[dispwin]="argyllcms"
	[libnotify]="libnotify"
	[xrandr]="xorg-xrandr"
	[networkmanager]="networkmanager"
)

# Debian-specific package names
declare -A DEBIAN_PACKAGES=(
	[dispwin]="argyll"
	[libnotify]="libnotify-bin"
	[xrandr]="x11-xserver-utils"
	[networkmanager]="network-manager"
)

# Always included, handled specially
declare -A SPECIAL_PACKAGES=(
	[nvim]="neovim"
	[alacritty]="alacritty"
	[betterlockscreen]="betterlockscreen"
	[fzf]="fzf"
	[miniconda]="miniconda"
	[node]="node"
	[rust]="rust"
	[easyeffects_fx]="easyeffects_fx"
	[thunar_fe]="thunar_fe"
	[i3lock_color]="i3lockcolor"
	[xidlehook]="xidlehook"
	[yazi]="yazi"
)

# ────────────────────────────────────────────────
# Combine into one final list depending on distro

declare -A ALL_PACKAGES

# Step 1: Add common packages
for key in "${!COMMON_PACKAGES[@]}"; do
	ALL_PACKAGES["$key"]="${COMMON_PACKAGES[$key]}"
done

# Step 3: Add distro-specific
case "$DISTRO" in
arch)
	for key in "${!ARCH_PACKAGES[@]}"; do
		ALL_PACKAGES["$key"]="${ARCH_PACKAGES[$key]}"
	done
	;;
debian)
	for key in "${!DEBIAN_PACKAGES[@]}"; do
		ALL_PACKAGES["$key"]="${DEBIAN_PACKAGES[$key]}"
	done
	;;
esac

# Step 2: Add special packages (not distro-specific)
for key in "${!SPECIAL_PACKAGES[@]}"; do
	ALL_PACKAGES["$key"]="${SPECIAL_PACKAGES[$key]}"
done

# ────────────────────────────────────────────────
# Show Msg function (Accepts one arg msg)
show_msg() {
	local msg="$1"
	cat <<EOF
$msg
EOF
}

# ────────────────────────────────────────────────
# Yes No prompt function (Accepts one arg as prompt msg)
ask_yes_no() {
	local prompt="$1"
	local reply

	while true; do
		read -r -p "$prompt [y/n]: " reply
		case "$reply" in
		[Yy] | [Yy][Ee][Ss]) return 0 ;; # true
		[Nn] | [Nn][Oo]) return 1 ;;     # false
		*) echo "Please answer y or n." ;;
		esac
	done
}

# ────────────────────────────────────────────────
# Package checker (returns missing packages in stdout)
check_packages() {
	local packages=("$@")
	local missing_pkgs=()

	if [ ${#packages[@]} -eq 0 ]; then
		log_error "No packages specified for checking"
		return 1
	fi

	case "$DISTRO" in
	arch)
		for pkg in "${packages[@]}"; do
			if ! pacman -Qi "$pkg" &>/dev/null; then
				missing_pkgs+=("$pkg")
			fi
		done
		;;
	debian)
		for pkg in "${packages[@]}"; do
			if ! dpkg -s "$pkg" &>/dev/null; then
				missing_pkgs+=("$pkg")
			fi
		done
		;;
	esac

	# Print missing packages (caller can capture with command substitution)
	echo "${missing_pkgs[@]}"
}

press_enter() {
	read -rp "Press Enter to continue" </dev/tty >/dev/tty
}

print_line() {
	case "$1" in
	-s) echo "-------- Start ---------" ;;
	-e) echo "--------- End ----------" ;;
	*) echo "Usage: print_line -s|-e" ;;
	esac
}

# ────────────────────────────────────────────────
# Package installations (official non official)
install_packages() {
	local -n arr=$1
	local mode=$2
	local array_name=$1

	# Separate regular and special packages
	local regular_packages=()
	local special_packages=()

	for pkg in "${arr[@]}"; do
		if [[ -n "${SPECIAL_PACKAGES[$pkg]}" ]]; then
			special_packages+=("${SPECIAL_PACKAGES[$pkg]}")
		else
			if [ "$mode" = "-n" ]; then
				regular_packages+=("${ALL_PACKAGES[$pkg]}")
			elif [ "$mode" = "-d" ]; then
				regular_packages+=("$pkg")
			fi
		fi
	done

	local missing_pkgs=()

	if [ ${#regular_packages[@]} -gt 0 ]; then
		read -ra missing_pkgs <<<"$(check_packages "${regular_packages[@]}")"
	fi
	echo "Regular pkgs: ${missing_pkgs[*]}"
	echo "Special pkgs: ${special_packages[*]}"

	local exit_code=0

	# Install regular packages first
	if [ ${#missing_pkgs[@]} -gt 0 ]; then
		log_info "Installing regular packages: ${missing_pkgs[*]}"
		case "$DISTRO" in
		arch)
			if sudo pacman -Sy --noconfirm "${missing_pkgs[@]}"; then
				log_success "Installed: ${missing_pkgs[*]}"
			else
				log_error "Failed to install: ${missing_pkgs[*]}"
				exit_code=1
			fi
			;;
		debian)
			if sudo apt-get update && sudo apt-get install -y "${missing_pkgs[@]}"; then
				log_success "Installed: ${missing_pkgs[*]}"
			else
				log_error "Failed to install: ${missing_pkgs[*]}"
				exit_code=1
			fi
			;;
		esac
	else
		log_info "Got no regular packages to install"
	fi

	# Install special packages one by one
	if [ ${#special_packages[@]} -gt 0 ]; then
		log_info "Installing special packages: ${special_packages[*]}"

		for pkg in "${special_packages[@]}"; do
			if ! install_special_packages "$pkg"; then
				exit_code=1
				break
			fi
		done
	else
		log_info "Got no special packages to install"
	fi

	return "$exit_code"
}

# ────────────────────────────────────────────────
# Special package installations (not in official repos)
install_special_packages() {
	local package_name=$1
	local support_pkgs=()
	: "${support_pkgs[@]}"

	case "$package_name" in
	xidlehook)
		log_info "Installing $package_name..."
		(
			local INSTALLED_VER
			local LATEST_VER

			# Check if already installed
			if command -v xidlehook >/dev/null 2>&1; then
				if [ -f "$SCRIPT_DIR/.version_$package_name" ]; then
					INSTALLED_VER=$(cat "$SCRIPT_DIR/.version_$package_name")
				else
					INSTALLED_VER=$(xidlehook --version | awk '{print $2}')
				fi
				LATEST_VER=$(curl -s https://api.github.com/repos/jD91mZM2/xidlehook/tags | grep '"name":' | head -n 1 | cut -d'"' -f4)

				if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
					log_info "$package_name is up-to-date (version $INSTALLED_VER)."
					log_success "$package_name is ready."
					return 0
				else
					log_info "Updating $package_name from $INSTALLED_VER → $LATEST_VER"
				fi
			fi

			log_info "Installing dependencies for $package_name..."

			case "$DISTRO" in
			arch)
				support_pkgs=(rust libxcb libxrandr libxss libx11 dbus)
				install_packages support_pkgs -d || return 1
				;;
			debian)
				support_pkgs=(rust libxcb1-dev libxcb-randr0-dev libxcb-dpms0-dev libxcb-screensaver0-dev libdbus-1-dev)
				install_packages support_pkgs -d || return 1
				;;
			esac

			# Clean old build if present
			[ -d /tmp/xidlehook ] && rm -rf /tmp/xidlehook

			LATEST_VER=$(curl -s https://api.github.com/repos/jD91mZM2/xidlehook/tags | grep '"name":' | head -n 1 | cut -d'"' -f4)

			# Build from source
			git clone https://github.com/jD91mZM2/xidlehook.git /tmp/xidlehook
			cd /tmp/xidlehook || return 1
			cargo build --release || return 1
			sudo install -Dm755 target/release/xidlehook /usr/local/bin/xidlehook

			# Cleanup
			cd "$SCRIPT_DIR" || return 1
			[ -d /tmp/xidlehook ] && rm -rf /tmp/xidlehook

			echo "$LATEST_VER" >"$SCRIPT_DIR/.version_$package_name"
		)
		log_success "Installed/Updated $package_name..."
		;;
	i3lockcolor)
		log_info "Installing $package_name..."

		(
			local INSTALLED_VER
			local LATEST_VER

			# Check if already installed
			if command -v i3lock >/dev/null 2>&1; then
				if [ -f "$SCRIPT_DIR/.version_$package_name" ]; then
					INSTALLED_VER=$(cat "$SCRIPT_DIR/.version_$package_name")
				else
					INSTALLED_VER=$(i3lock --version 2>&1 | awk '{print $3}')
				fi
				LATEST_VER=$(curl -s https://api.github.com/repos/Raymo111/i3lock-color/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

				if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
					log_info "$package_name is up-to-date (version $INSTALLED_VER)."
					log_success "$package_name is ready."
					return 0
				else
					log_info "Updating $package_name from $INSTALLED_VER → $LATEST_VER"
				fi
			fi

			log_info "Installing dependencies for $package_name..."

			case "$DISTRO" in
			arch)
				support_pkgs=(autoconf cairo fontconfig gcc libev libjpeg-turbo libxinerama libxkbcommon-x11 libxrandr pam pkgconf
					xcb-util-image xcb-util-xrm imagemagick xorg-xdpyinfo xorg-xrdb xorg-xset)
				install_packages support_pkgs -d || return 1
				;;
			debian)
				support_pkgs=(autoconf gcc make pkg-config libpam0g-dev libcairo2-dev libfontconfig1-dev libxcb-composite0-dev libev-dev
					libx11-xcb-dev libxcb-xkb-dev libxcb-xinerama0-dev libxcb-randr0-dev libxcb-image0-dev libxcb-util0-dev libxcb-xrm-dev
					libxkbcommon-dev libxkbcommon-x11-dev libjpeg-dev libgif-dev imagemagick x11-utils)
				install_packages support_pkgs -d || return 1
				;;
			esac

			# Clean old build if present
			[ -d /tmp/i3lock-color ] && rm -rf /tmp/i3lock-color

			LATEST_VER=$(curl -s https://api.github.com/repos/Raymo111/i3lock-color/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

			# Build from source
			git clone https://github.com/Raymo111/i3lock-color.git /tmp/i3lock-color
			cd /tmp/i3lock-color || return 1
			./install-i3lock-color.sh
			cd "$SCRIPT_DIR" || return 1
			[ -d /tmp/i3lock-color ] && rm -rf /tmp/i3lock-color

			echo "$LATEST_VER" >"$SCRIPT_DIR/.version_$package_name"
		)
		log_success "Installed/Updated $package_name..."
		;;
	betterlockscreen)
		log_info "Installing $package_name..."

		(
			local INSTALLED_VER
			local LATEST_VER
			# Check if already installed
			if command -v betterlockscreen >/dev/null 2>&1; then
				if [ -f "$SCRIPT_DIR/.version_$package_name" ]; then
					INSTALLED_VER=$(cat "$SCRIPT_DIR/.version_$package_name")
				else
					INSTALLED_VER=$(betterlockscreen --version 2>&1 | grep -m1 '^Betterlockscreen:' | awk '{print $3}')
				fi
				LATEST_VER=$(curl -s https://api.github.com/repos/betterlockscreen/betterlockscreen/tags | grep -m1 '"name": "v4.3.0"' | cut -d'"' -f4)

				if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
					log_info "$package_name is up-to-date (version $INSTALLED_VER)."
					log_success "$package_name is ready."
					return 0
				else
					log_info "Updating $package_name from $INSTALLED_VER → $LATEST_VER"
				fi
			fi

			log_info "Installing dependencies for $package_name..."
			support_pkgs=(i3lock_color bc)
			install_packages support_pkgs -d || return 1

			# Clean old build if present
			[ -d /tmp/betterlockscreen-main ] && rm -rf /tmp/betterlockscreen-main
			[ -f /tmp/betterlockscreen.zip ] && rm -rf /tmp/betterlockscreen.zip

			LATEST_VER=$(curl -s https://api.github.com/repos/betterlockscreen/betterlockscreen/tags | grep -m1 '"name": "v4.3.0"' | cut -d'"' -f4)

			# Download and install latest
			wget -O /tmp/betterlockscreen.zip https://github.com/betterlockscreen/betterlockscreen/archive/refs/heads/main.zip
			unzip /tmp/betterlockscreen.zip -d /tmp
			cd /tmp/betterlockscreen-main || return 1
			chmod u+x betterlockscreen
			sudo cp betterlockscreen /usr/local/bin/

			# Cleanup
			cd "$SCRIPT_DIR" || return 1
			[ -d /tmp/betterlockscreen-main ] && rm -rf /tmp/betterlockscreen-main
			[ -f /tmp/betterlockscreen.zip ] && rm -rf /tmp/betterlockscreen.zip

			echo "$LATEST_VER" >"$SCRIPT_DIR/.version_$package_name"
		)
		log_success "Installed/Updated $package_name..."
		;;
	alacritty)
		log_info "Installing $package_name..."

		(
			local INSTALLED_VER
			local LATEST_VER

			# Check if already installed
			if command -v alacritty >/dev/null 2>&1; then
				INSTALLED_VER=$(alacritty --version 2>&1 | awk '{print "v"$2}')
				LATEST_VER=$(curl -s https://api.github.com/repos/alacritty/alacritty/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

				if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
					log_info "$package_name is up-to-date (version $INSTALLED_VER)."
					log_success "$package_name is ready."
					return 0
				else
					log_info "Updating $package_name from $INSTALLED_VER → $LATEST_VER"
				fi
			fi

			log_info "Installing Desps for $package_name"

			case "$DISTRO" in
			arch)
				support_pkgs=(cmake freetype2 fontconfig pkg-config make libxcb libxkbcommon python gzip scdoc rust)
				install_packages support_pkgs -d || return 1
				;;
			debian)
				support_pkgs=(cmake g++ pkg-config libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev python3 gzip scdoc rust)
				install_packages support_pkgs -d || return 1
				;;
			esac

			# Clean old build if present
			[ -d /tmp/alacritty ] && rm -rf /tmp/alacritty

			# Download and install latest
			git clone https://github.com/alacritty/alacritty.git /tmp/alacritty || return 1
			cd /tmp/alacritty || return 1

			LATEST_VER=$(curl -s https://api.github.com/repos/alacritty/alacritty/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

			git checkout "tags/$LATEST_VER" -b "build-$LATEST_VER" || return 1

			# Build release binary
			cargo build --release || return 1

			# Install binary
			sudo cp target/release/alacritty /usr/local/bin || return 1

			# Install icon + desktop entry
			sudo cp extra/logo/alacritty-term.svg /usr/share/pixmaps/Alacritty.svg || return 1
			sudo desktop-file-install extra/linux/Alacritty.desktop || return 1
			sudo update-desktop-database || return 1

			# Install man pages
			sudo mkdir -p /usr/local/share/man/man{1,5} || return 1
			scdoc <extra/man/alacritty.1.scd | gzip -c | sudo tee /usr/local/share/man/man1/alacritty.1.gz >/dev/null || return 1
			scdoc <extra/man/alacritty-msg.1.scd | gzip -c | sudo tee /usr/local/share/man/man1/alacritty-msg.1.gz >/dev/null || return 1
			scdoc <extra/man/alacritty.5.scd | gzip -c | sudo tee /usr/local/share/man/man5/alacritty.5.gz >/dev/null || return 1
			scdoc <extra/man/alacritty-bindings.5.scd | gzip -c | sudo tee /usr/local/share/man/man5/alacritty-bindings.5.gz >/dev/null || return 1

			# Cleanup
			cd "$SCRIPT_DIR" || return 1
			[ -d /tmp/alacritty ] && rm -rf /tmp/alacritty || return 1
		)

		log_success "Installed/Updated $package_name..."
		;;
	neovim)
		log_info "Installing $package_name"

		(
			local INSTALLED_VER
			local LATEST_VER

			# Check if already installed
			if command -v nvim >/dev/null 2>&1; then
				INSTALLED_VER=$(nvim -v | head -n1 | awk '{print $2}')
				LATEST_VER=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

				if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
					log_info "$package_name is up-to-date (version $INSTALLED_VER)."
					log_success "$package_name is ready."
					return 0
				else
					log_info "Updating $package_name from $INSTALLED_VER → $LATEST_VER"
				fi
			fi

			log_info "Installing Desps for $package_name"

			case "$DISTRO" in
			arch)
				support_pkgs=(cmake ninja tree-sitter curl unzip gettext)
				install_packages support_pkgs -d || return 1
				;;
			debian)
				support_pkgs=(ninja-build gettext cmake unzip curl build-essential
					pkg-config libtool libtool-bin autoconf automake g++ tree-sitter-cli)
				install_packages support_pkgs -d || return 1
				;;
			esac

			# Clean old build if present
			[ -d /tmp/neovim ] && rm -rf /tmp/neovim

			# Clone source
			git clone https://github.com/neovim/neovim /tmp/neovim
			cd /tmp/neovim || return 1

			LATEST_VER=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

			git checkout "tags/$LATEST_VER" -b "build-$LATEST_VER" || return 1

			# Build (release mode)
			make CMAKE_BUILD_TYPE=Release

			# Install system-wide
			sudo make install

			# Cleanup
			cd "$SCRIPT_DIR" || return 1
			[ -d /tmp/neovim ] && rm -rf /tmp/neovim
		)
		log_success "Installed $package_name"
		;;
	yazi)
		log_info "Installing $package_name"

		(
			local INSTALLED_VER
			local LATEST_VER

			# Check if already installed
			if command -v yazi >/dev/null 2>&1; then
				INSTALLED_VER=$(yazi --version | awk '{print "v"$2}')
				LATEST_VER=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

				if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
					log_info "$package_name is up-to-date (version $INSTALLED_VER)."
					log_success "$package_name is ready."
					return 0
				else
					log_info "Updating $package_name from $INSTALLED_VER → $LATEST_VER"
				fi
			fi

			log_info "Installing deps for $package_name"

			case "$DISTRO" in
			arch)
				support_pkgs=(ffmpeg 7zip jq poppler fd ripgrep zoxide resvg imagemagick rust)
				install_packages support_pkgs -d || return 1
				;;
			debian)
				support_pkgs=(ffmpeg p7zip-full jq poppler-utils fd-find ripgrep zoxide librsvg2-bin imagemagick unzip curl rust)
				install_packages support_pkgs -d || return 1
				;;
			esac

			# Clean old build if present
			[ -d /tmp/yazi ] && rm -rf /tmp/yazi

			LATEST_VER=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

			git clone https://github.com/sxyazi/yazi.git /tmp/yazi
			cd /tmp/yazi || return 1

			git checkout "tags/$LATEST_VER" -b "build-$LATEST_VER" || return 1

			cargo build --release --locked

			# Install binaries
			sudo mv target/release/yazi target/release/ya /usr/local/bin/

			# Cleanup
			cd "$SCRIPT_DIR" || return 1
			[ -d /tmp/yazi ] && rm -rf /tmp/yazi
		)
		log_success "Installed $package_name"
		;;
	rust)
		log_info "Installing $package_name"

		if command -v cargo >/dev/null 2>&1; then
			log_info "Rust is already installed (system or rustup)."
		else
			log_info "Rust not found, installing with rustup..."
			curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || return 1
		fi

		# If rustup install, source cargo env
		if [ -f "$HOME/.cargo/env" ]; then
			# shellcheck source=/dev/null
			source "$HOME/.cargo/env"
			log_info "Sourced rustup environment."
			return 0
		fi

		log_success "Installed $package_name"
		;;
	node)
		log_info "Installing $package_name..."

		if command -v node >/dev/null 2>&1; then
			log_info "Node is already installed..."
		else
			log_info "Node not found, installing with NVM"
			curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
		fi

		if [ -d "$HOME/.nvm" ]; then
			# in lieu of restarting the shell
			export NVM_DIR="$HOME/.nvm"

			# shellcheck disable=SC1090
			. "$NVM_DIR/nvm.sh" || return 1

			# Download and install Node.js:
			nvm install 22 || return 1

			log_info "Sourced nvm environment and installed node."
		fi

		log_success "Installed $package_name..."
		;;
	fzf)
		log_info "Installing $package_name..."

		# Check if already installed
		if command -v fzf >/dev/null 2>&1; then
			INSTALLED_VER=$(fzf --version | awk '{print "v"$1}')
			LATEST_VER=$(curl -s https://api.github.com/repos/junegunn/fzf/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

			if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
				log_info "$package_name is up-to-date (version $INSTALLED_VER)."
				log_success "$package_name is ready."
				return 0
			else
				log_info "Updating $package_name from $INSTALLED_VER → $LATEST_VER"
			fi
		fi

		[ -d "$HOME/.fzf" ] && rm -rf "$HOME/.fzf"

		# Download and install latest
		git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf || return 1
		~/.fzf/install

		local shell_name
		shell_name=$(ps -p $$ -o comm=)

		case "$shell_name" in
		bash) source "$HOME/.fzf.bash" ;;
		zsh) source "$HOME/.fzf.zsh" ;;
		esac

		log_success "Installed $package_name..."
		;;
	miniconda)
		log_info "Installing $package_name..."

		# Check if already installed
		if command -v conda >/dev/null 2>&1 || type conda >/dev/null 2>&1; then
			log_success "conda is ready."
			return 0
		fi

		# Download latest
		wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh || return 1

		# Clean old if present
		[ -d "$HOME/miniconda3" ] && rm -rf "$HOME/miniconda3"

		# Install
		chmod +x ./Miniconda3-latest-Linux-x86_64.sh
		./Miniconda3-latest-Linux-x86_64.sh

		# Cleanup
		[ -f ./Miniconda3-latest-Linux-x86_64.sh ] && rm -rf ./Miniconda3-latest-Linux-x86_64.sh

		# Detect shell
		local CURRENT_SHELL
		CURRENT_SHELL=$(ps -p $$ -o comm=)

		if [[ "$CURRENT_SHELL" == "bash" || "$CURRENT_SHELL" == "zsh" ]]; then
			if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
				source "$HOME/miniconda3/etc/profile.d/conda.sh"
			elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
				source "$HOME/anaconda3/etc/profile.d/conda.sh"
			else
				echo "conda.sh not found!"
			fi
		else
			echo "Unsupported shell: $CURRENT_SHELL"
		fi

		log_success "Installed $package_name..."
		;;
	easyeffects_fx)
		log_info "Installing $package_name..."
		log_info "Installing Desps for $package_name"

		case "$DISTRO" in
		arch)
			# Core dependencies
			support_pkgs=(easyeffects calf lsp-plugins-lv2 zam-plugins-lv2 mda.lv2)
			install_packages support_pkgs -d || return 1
			;;
		debian)
			# Core dependencies
			support_pkgs=(easyeffects lsp-plugins-lv2 lsp-plugins calf-plugins mda-lv2 zam-plugins)
			install_packages support_pkgs -d || return 1
			;;
		esac

		log_success "Installed $package_name..."
		;;
	thunar_fe)
		log_info "Installing $package_name..."
		log_info "Installing Desps for $package_name"

		case "$DISTRO" in
		arch)
			# Core dependencies
			support_pkgs=(thunar thunar-volman gvfs gvfs-mtp gvfs-smb gvfs-afc gvfs-goa exo
				tumbler libmtp fuse2 xdg-user-dirs)
			install_packages support_pkgs -d || return 1
			;;
		debian)
			# Core dependencies
			support_pkgs=(thunar thunar-volman gvfs gvfs-backends gvfs-fuse exo-utils tumbler
				libmtp9 fuse xdg-user-dirs mtp-tools)
			install_packages support_pkgs -d || return 1
			;;
		esac

		log_success "Installed $package_name..."
		;;
	coolercontrol)
		log_info "Installing $package_name..."

		# Check if already installed
		if command -v coolercontrold >/dev/null 2>&1; then
			INSTALLED_VER=$(coolercontrold --version 2>&1 | grep -oP 'CoolerControlD \K[0-9.]+')
			LATEST_VER=$(curl -s "https://gitlab.com/api/v4/projects/coolercontrol%2Fcoolercontrol/releases" |
				grep -oP '"tag_name":"\K[^"]+' | head -n1)

			if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
				log_info "$package_name is up-to-date (version $INSTALLED_VER)."
				log_success "$package_name is ready."
				return 0
			else
				log_info "Updating $package_name from $INSTALLED_VER → $LATEST_VER"
			fi
		fi

		log_info "Installing Desps for $package_name"
		case "$DISTRO" in
		arch)
			# Core dependencies + plugins (AUR)
			support_pkgs=(lm_sensors)
			install_packages support_pkgs -d || return 1
			;;
		debian)
			# Core dependencies
			support_pkgs=(lm-sensors)
			install_packages support_pkgs -d || return 1
			;;
		esac

		# Clone the repo
		git clone https://gitlab.com/ccoolercontroloolercontrol/coolercontrol.git /tmp/coolercontrol
		cd /tmp/coolercontrol || exit 1

		# Switch to main branch and pull latest
		git checkout main
		git pull

		# Build & install all components
		make install-source -j4

		# Enable daemon
		sudo systemctl daemon-reload
		sudo systemctl enable --now coolercontrold

		# Clean up
		cd "$SCRIPT_DIR" || return 1
		rm -rf /tmp/coolercontrol

		log_success "Installed $package_name..."

		show_msg "lm-sensors and coolercontrol is installed
but in case if you don't see any sensors or
system stats in the cooler control UI then
simply just run sudo lm-sensors or for one
time just turn of the secure boot and then
do sudo lm-sensors."
		;;
	esac
	return 0
}

install_from_array() {
	local -n arr=$1 # create a nameref to the array
	local mode=$2
	local array_name=$1

	if [ "$mode" = "all" ]; then
		# Get all package values
		local all_packages=()
		for key in "${!arr[@]}"; do
			all_packages+=("$key")
		done

		log_info "Installing all packages from $array_name..."

		if install_packages all_packages -n; then
			log_success "Successfully installed all packages from all_packages"
			press_enter
			return 0
		else
			log_error "Failed to install some packages from all_packages"
			press_enter
			return 1
		fi
	elif [ "$mode" = "select" ]; then
		local msg=""
		local selected_pkg=()
		declare -A index_pkg=()
		while true; do
			clear
			local choice=""
			local i=1

			echo "=== Select to install ==="
			for key in "${!arr[@]}"; do
				echo "$i) $key: ${arr[$key]}"
				index_pkg[$i]="$key"
				((i++))
			done

			# Show install option if something is selected
			if [ ${#selected_pkg[@]} -gt 0 ]; then
				echo "$i) Install selected packages"
				local install_option=$i
				((i++))
			fi

			echo "$i) Back"
			local back_option=$i

			echo
			echo "$msg"
			read -rp "Enter your choice: " choice </dev/tty >/dev/tty

			# Check if input is a valid number
			if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
				msg="Invalid option: not a number"
				continue
			fi

			# Check for back option
			if [ "$choice" -eq "$back_option" ]; then
				return 0
			fi

			# Check for install option
			if [ -n "${install_option:-}" ] && [ "$choice" -eq "$install_option" ]; then
				if install_packages selected_pkg -n; then
					log_success "Successfully installed all packages from selected_pkg"
					press_enter
					return 0
				else
					log_error "Failed to install some packages from selected_pkg"
					press_enter
					return 1
				fi
			fi

			# Check if input maps to a valid package
			if [ -z "${index_pkg[$choice]}" ]; then
				msg="Invalid option: out of range"
				continue
			fi

			# Check if package is already selected
			pkg="${index_pkg[$choice]}"
			found=0
			for sel in "${selected_pkg[@]}"; do
				if [ "$sel" = "$pkg" ]; then
					found=1
					break
				fi
			done

			if [ "$found" -eq 1 ]; then
				msg="Package '$pkg' is already selected"
			else
				selected_pkg+=("$pkg")
				msg=""
			fi
		done
	fi
}

install_i3wm_setup() {
	print_line -s
	local msg=""
	local choice=""
	while true; do
		clear
		echo
		echo "=== i3wm Setup Packages ==="
		echo "1) Install all i3 setup tools"
		echo "2) Select tools to install"
		echo "3) Back to main menu"
		echo "$msg"
		echo "=============================="
		read -rp "Choose an option: " choice </dev/tty >/dev/tty

		case "$choice" in
		1)
			install_from_array I3_PACKAGES_DESC "all"
			msg=""
			;;
		2)
			install_from_array I3_PACKAGES_DESC "select"
			msg=""
			;;
		3) return ;;
		*)
			msg="Invalid option '$choice'"
			;;
		esac
	done
	print_line -e
}

install_dev_tools() {
	print_line -s
	local msg=""
	local choice=""
	while true; do
		clear
		echo
		echo "=== Dev Tools Installation ==="
		echo "1) Install all dev tools"
		echo "2) Select tools to install"
		echo "3) Back to main menu"
		echo "$msg"
		echo "=============================="
		read -rp "Choose an option: " choice </dev/tty >/dev/tty

		case "$choice" in
		1)
			install_from_array DEV_PACKAGES_DESC "all"
			msg=""
			;;
		2)
			install_from_array DEV_PACKAGES_DESC "select"
			msg=""
			;;
		3) return ;;
		*)
			msg="Invalid option '$choice'"
			;;
		esac
	done
	print_line -e
}

declare -A ALL_CONFIGS=(
	[alacritty]="alacritty config"
	[bash]=".bashrc config"
	[betterlockscreen]="betterlockscreen config"
	[clangformat]="c language formatting config"
	[dunst]="notification manager config"
	[i3]="i3wm config"
	[nvim]="neovim config based on lazyvim setup"
	[picom]="picom config for animation and transperency for TWM"
	[polybar]="task bar config"
	[rofi]="config for menues in TWM"
	[tmux]="tmux config with vim motions"
	[xinitrc]="config for TWM start up"
	[yazi]="config for terminal based file manager"
	[zsh]="shell config with better vim motion support"
)
: "${ALL_CONFIGS[@]}"

declare -A ALL_CONFIGS_PATHS=(
	[alacritty]="$HOME/.config/alacritty/alacritty.yml"
	[bash]="$HOME/.bashrc"
	[betterlockscreen]="$HOME/.config/betterlockscreen/betterlockscreenrc"
	[clangformat]="$HOME/.clang-format"
	[dunst]="$HOME/.config/dunst/dunstrc"
	[i3]="$HOME/.config/i3/config"
	[nvim]="$HOME/.config/nvim"
	[picom]="$HOME/.config/picom/picom.conf"
	[polybar]="$HOME/.config/polybar/config"
	[rofi]="$HOME/.config/rofi/config.rasi"
	[tmux]="$HOME/.tmux.conf"
	[xinitrc]="$HOME/.xinitrc"
	[yazi]="$HOME/.config/yazi/config.toml"
	[zsh]="$HOME/.zshrc"
)
: "${ALL_CONFIGS_PATHS[@]}"

set_config() {
	local -n arr=$1 # Reference to passed array of keys
	local source_dir="$HOME/.dotfiles"

	# Ensure .dotfiles repo is cloned
	if [ ! -d "$source_dir" ]; then
		echo "Cloning dotfiles repo..."
		git clone https://github.com/rushin236/.dotfiles.git "$source_dir" || return 1
	fi

	for key in "${arr[@]}"; do
		local target="${ALL_CONFIGS_PATHS[$key]}"

		if [ -z "$target" ]; then
			echo "⚠️  Unknown key: $key"
			continue
		fi

		echo "Processing: $key → $target"

		# Backup existing config if it exists
		if [ -e "$target" ] || [ -L "$target" ]; then
			local backup="${target}.bak"
			echo "Backing up $target → $backup"
			mv -f "$target" "$backup"
		fi

		# Run stow
		echo "Stowing $key..."
		stow --target="$HOME" --dir="$source_dir" "$key"
	done

	return 0
}

setup_config_from_array() {
	local -n arr=$1 # create a nameref to the array
	local mode=$2
	local array_name=$1

	if [ "$mode" = "all" ]; then
		# Get all package values
		local all_configs=()
		for key in "${!arr[@]}"; do
			all_configs+=("$key")
		done

		log_info "Setting up all configs from $array_name..."

		if set_config all_configs; then
			log_success "Successfully setup all configs from all_configs"
			press_enter
			return 0
		else
			log_error "Failed to setup some configs from all_configs"
			press_enter
			return 1
		fi
	elif [ "$mode" = "select" ]; then
		local msg=""
		local selected_configs=()
		declare -A index_configs=()
		while true; do
			clear
			local choice=""
			local i=1

			echo "=== Select to setup ==="
			for key in "${!arr[@]}"; do
				echo "$i) $key: ${arr[$key]}"
				index_configs[$i]="$key"
				((i++))
			done

			# Show install option if something is selected
			if [ ${#selected_configs[@]} -gt 0 ]; then
				echo "$i) Setup selected configs"
				local install_option=$i
				((i++))
			fi

			echo "$i) Back"
			local back_option=$i

			echo
			echo "$msg"
			read -rp "Enter your choice: " choice </dev/tty >/dev/tty

			# Check if input is a valid number
			if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
				msg="Invalid option: not a number"
				continue
			fi

			# Check for back option
			if [ "$choice" -eq "$back_option" ]; then
				return 0
			fi

			# Check for install option
			if [ -n "${install_option:-}" ] && [ "$choice" -eq "$install_option" ]; then
				if set_config selected_configs; then
					log_success "Successfully setup all configs from selected_configs"
					press_enter
					return 0
				else
					log_error "Failed to setup some configs from selected_configs"
					press_enter
					return 1
				fi
			fi

			# Check if input maps to a valid package
			if [ -z "${index_configs[$choice]}" ]; then
				msg="Invalid option: out of range"
				continue
			fi

			# Check if package is already selected
			local config
			config="${index_configs[$choice]}"
			found=0
			for sel in "${selected_configs[@]}"; do
				if [ "$sel" = "$config" ]; then
					found=1
					break
				fi
			done

			if [ "$found" -eq 1 ]; then
				msg="Config '$config' is already selected"
			else
				selected_configs+=("$config")
				msg=""
			fi
		done
	fi
}

setup_config() {
	print_line -s
	local msg=""
	local choice=""
	while true; do
		clear
		echo
		echo "======= Config Setup  ========"
		echo "1) Setup all configs"
		echo "2) Select configs to setup"
		echo "3) Back to main menu"
		echo "$msg"
		echo "=============================="
		read -rp "Choose an option: " choice </dev/tty >/dev/tty

		case "$choice" in
		1)
			setup_config_from_array ALL_CONFIGS "all"
			msg=""
			;;
		2)
			setup_config_from_array ALL_CONFIGS "select"
			msg=""
			;;
		3) return ;;
		*)
			msg="Invalid option '$choice'"
			;;
		esac
	done
	print_line -e
}

main_menu() {
	local msg=""
	local choice=""
	while true; do
		clear
		echo
		echo "=== Setup Menu (Distro: $DISTRO | Arch: $MACHINE) ==="
		echo "1) Install i3wm setup"
		echo "2) Install dev tools"
		echo "3) Setup i3wm and dev tools config"
		echo "4) Exit"
		echo "$msg"
		echo "====================================================="
		read -rp "Choose an option: " choice </dev/tty >/dev/tty

		case "$choice" in
		1)
			install_i3wm_setup
			msg=""
			;;
		2)
			install_dev_tools
			msg=""
			;;
		3)
			setup_config
			msg=""
			;;
		4)
			echo "Bye!"
			exit 0
			;;
		*)
			msg="Invalid option '$choice'"
			;;
		esac
	done
}

install_required_packages() {
	local required_pkgs=()

	case "$DISTRO" in
	arch)
		required_pkgs=(wget base-devel unzip curl make python libdrm stow)
		;;
	debian)
		required_pkgs=(wget build-essential unzip curl make python3 python3-pip libdrm-dev stow)
		;;
	*)
		log_error "Unsupported distro: $DISTRO"
		exit 1
		;;
	esac

	log_info "Checking required packages..."
	local missing_pkgs

	read -ra missing_pkgs <<<"$(check_packages "${required_pkgs[@]}")"

	if [ ${#missing_pkgs[@]} -ne 0 ]; then
		log_info "Missing packages: ${missing_pkgs[*]}"
		if install_packages missing_pkgs -d; then
			log_success "Successfully installed all required packages ${missing_pkgs[*]}"
			return 0
		else
			log_error "Failed to install some packages"
			return 1
		fi
	else
		log_success "All required packages ${required_pkgs[*]} are already installed"
		return 0
	fi
}

if ! install_required_packages; then
	log_error "Some error occured exiting install script!"
	exit 1
fi

main_menu
