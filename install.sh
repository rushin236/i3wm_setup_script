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
	[betterlockscreen]="Simple lockscreen session locker for i3wm (installed via script)"
	[xrandr]="Interact with the X RandR extension to set screen size/position"
	[autorandr]="Auto-detect and use saved XRandR profiles"
	[dispwin]="Load ICC profiles into the display system (from ArgyllCMS)"
	[wireplumber]="Session and policy manager for PipeWire"
	[libnotify]="Library for sending desktop notifications"
)
: "${I3_PACKAGES_DESC[@]}"

# Dev tools packages
declare -A DEV_PACKAGES_DESC=(
	[nvim]="Modern Vim-based text editor"
	[alacritty]="GPU-accelerated terminal emulator"
	[tmux]="Terminal multiplexer for managing sessions"
	[zsh]="Powerful interactive shell"
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
	[nvim]="neovim"
	[tmux]="tmux"
	[zsh]="zsh"
)

# Arch-specific package names
declare -A ARCH_PACKAGES=(
	[dispwin]="argyllcms"
	[libnotify]="libnotify"
	[xrandr]="xorg-xrandr"
)

# Debian-specific package names
declare -A DEBIAN_PACKAGES=(
	[dispwin]="argyll"
	[libnotify]="libnotify-bin"
	[xrandr]="x11-xserver-utils"
)

# Always included, handled specially
declare -A SPECIAL_PACKAGES=(
	[alacritty]="alacritty"
	[betterlockscreen]="betterlockscreen"
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
	*)
		log_error "Unsupported distro: $DISTRO"
		exit 1
		;;
	esac

	# Print missing packages (caller can capture with command substitution)
	echo "${missing_pkgs[@]}"
}

press_enter() {
	read -rp "Press Enter to continue"
}

# ────────────────────────────────────────────────
# Special package installations (not in official repos)
install_special_packages() {
	local package_name=$1

	case "$package_name" in
	betterlockscreen)
		log INFO "Installing betterlockscreen from GitHub..."
		if wget https://raw.githubusercontent.com/betterlockscreen/betterlockscreen/main/install.sh -O - -q | bash -s user; then
			log_success "Installed betterlockscreen"
			return 0
		else
			log_error "Failed to install betterlockscreen"
			return 1
		fi
		;;
	alacritty)
		log_info "Installing alacritty from GitHub..."
		log_info "Installing dependencies for alacritty..."

		# Install Rustup
		if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
			log_error "Failed to install rustup"
			return 1
		fi

		# Set env for cargo (important in same shell)
		export PATH="$HOME/.cargo/bin:$PATH"

		case "$DISTRO" in
		arch)
			install_packages cmake freetype2 fontconfig pkg-config make libxcb libxkbcommon python gzip scdoc || return 1
			;;
		debian)
			install_packages cmake g++ pkg-config libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev python3 gzip scdoc || return 1
			;;
		*)
			log_error "Unsupported distro: $DISTRO"
			return 1
			;;
		esac

		git clone https://github.com/alacritty/alacritty.git || return 1
		cd alacritty || return 1
		cargo build --release || return 1

		sudo cp target/release/alacritty /usr/local/bin || return 1
		sudo cp extra/logo/alacritty-term.svg /usr/share/pixmaps/Alacritty.svg || return 1
		sudo desktop-file-install extra/linux/Alacritty.desktop || return 1
		sudo update-desktop-database || return 1

		sudo mkdir -p /usr/local/share/man/man{1,5} || return 1
		scdoc <extra/man/alacritty.1.scd | gzip -c | sudo tee /usr/local/share/man/man1/alacritty.1.gz >/dev/null || return 1
		scdoc <extra/man/alacritty-msg.1.scd | gzip -c | sudo tee /usr/local/share/man/man1/alacritty-msg.1.gz >/dev/null || return 1
		scdoc <extra/man/alacritty.5.scd | gzip -c | sudo tee /usr/local/share/man/man5/alacritty.5.gz >/dev/null || return 1
		scdoc <extra/man/alacritty-bindings.5.scd | gzip -c | sudo tee /usr/local/share/man/man5/alacritty-bindings.5.gz >/dev/null || return 1

		cd "$SCRIPT_DIR" || return 1
		log_success "Installed alacritty"
		return 0
		;;
	*)
		log_error "Unknown special package: $package_name"
		return 1
		;;
	esac
}

install_packages() {
	local packages=("$@")

	# Separate regular and special packages
	local regular_packages=()
	local special_packages=()

	for pkg in "${packages[@]}"; do
		if [[ -n "${SPECIAL_PACKAGES[$pkg]}" ]]; then
			special_packages+=("${SPECIAL_PACKAGES[$pkg]}")
		else
			regular_packages+=("${ALL_PACKAGES[$pkg]}")
		fi
	done

	# Install regular packages first
	if [ ${#regular_packages[@]} -gt 0 ]; then
		case "$DISTRO" in
		arch)
			if sudo pacman -Sy --noconfirm "${regular_packages[@]}"; then
				log_success "Installed: ${regular_packages[*]}"
				return 0
			else
				log_error "Failed to install: ${regular_packages[*]}"
				return 1
			fi
			;;
		debian)
			if sudo apt-get update && sudo apt-get install -y "${regular_packages[@]}"; then
				log_success "Installed: ${regular_packages[*]}"
				return 0
			else
				log_error "Failed to install: ${regular_packages[*]}"
				return 1
			fi
			;;
		*)
			log_error "Unsupported distro: $DISTRO"
			return 1
			;;
		esac
	fi

	# Install special packages one by one
	if [ ${#special_packages[@]} -gt 0 ]; then
		log_info "Installing special packages..."

		for pkg in "${special_packages[@]}"; do
			if ! install_special_packages "$pkg"; then
				return 1
			fi
		done
		return 0
	fi
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

		if install_packages "${all_packages[@]}"; then
			log_success "Successfully installed all packages from $array_name"
			press_enter
			return 0
		else
			log_error "Failed to install some packages from $array_name"
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
			read -rp "Enter your choice: " choice

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
				if install_packages "${all_packages[@]}"; then
					log_success "Successfully installed all packages from $array_name"
					press_enter
					return 0
				else
					log_error "Failed to install some packages from $array_name"
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
		read -rp "Choose an option: " choice

		case "$choice" in
		1)
			install_from_array I3_PACKAGES_DESC "all"
			msg=""
			continue
			;;
		2)
			install_from_array I3_PACKAGES_DESC "select"
			msg=""
			continue
			;;
		3) return ;;
		*)
			msg="Invalid option '$choice'"
			;;
		esac
	done
}

install_dev_tools() {
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
		read -rp "Choose an option: " choice

		case "$choice" in
		1)
			install_from_array DEV_PACKAGES_DESC "all"
			msg=""
			continue
			;;
		2)
			install_from_array DEV_PACKAGES_DESC "select"
			msg=""
			continue
			;;
		3) return ;;
		*)
			msg="Invalid option '$choice'"
			;;
		esac
	done
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
		echo "3) Exit"
		echo "$msg"
		echo "====================================================="
		read -rp "Choose an option: " choice

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
	arch) required_pkgs=(wget base-devel) ;;
	debian) required_pkgs=(wget build-essential) ;;
	*)
		log ERROR "Unsupported distro: $DISTRO"
		exit 1
		;;
	esac

	log INFO "Checking required packages..."
	local missing_pkgs

	read -ra missing_pkgs <<<"$(check_packages "${required_pkgs[@]}")"

	if [ ${#missing_pkgs[@]} -ne 0 ]; then
		log_info "Missing packages: ${missing_pkgs[*]}"
		if install_packages "${missing_pkgs[@]}"; then
			log_success "Successfully installed all required packages ${required_pkgs[*]}"
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
