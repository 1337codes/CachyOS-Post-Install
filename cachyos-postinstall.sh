#!/usr/bin/env bash
# =============================================================================
# CachyOS Post-Install — Daily Apps + Pentest Toolkit + KDE Menu
# =============================================================================
#
# Installs:
#   - Daily apps:    Google Chrome, Joplin, VS Code (MS), Ghostty
#   - Dev tools:     git, base-devel, python (2 + 3), nodejs, go, rust, fish
#   - Pentest tools: blackarch-officials metapackage + curated extras
#   - Kali defaults: python2, netcat, rlwrap, feroxbuster, etc.
#   - Wordlists:     seclists, wordlists, rockyou (auto-decompressed)
#   - KDE Menu:      BlackArch-style categories (Recon, Web, Cracker, etc.)
#
# USAGE:
#   ./cachyos-postinstall.sh             # interactive
#   ./cachyos-postinstall.sh --yes       # non-interactive, accept all
#   ./cachyos-postinstall.sh --skip-pentest   # only daily apps + dev tools
#   ./cachyos-postinstall.sh --skip-menu      # don't touch KDE menu
#
# REQUIREMENTS:
#   - CachyOS Linux (or Arch with cachyos repos)
#   - Run as your normal user (script sudo's where needed)
#   - Internet connection
#   - ~5 GB disk space
#
# =============================================================================

set -uo pipefail

# =============================================================================
# Refuse root
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Don't run as root. Run as your normal user; the script sudos as needed." >&2
    exit 1
fi

if ! sudo -v; then
    echo "ERROR: sudo access required" >&2
    exit 1
fi

# Keep sudo alive
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT

# =============================================================================
# Config
# =============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cachyos-postinstall"
readonly LOG_FILE="$LOG_DIR/postinstall-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

# =============================================================================
# Output helpers
# =============================================================================
readonly C_RESET=$'\033[0m'
readonly C_RED=$'\033[31m'
readonly C_GREEN=$'\033[32m'
readonly C_YELLOW=$'\033[33m'
readonly C_BLUE=$'\033[34m'
readonly C_BOLD=$'\033[1m'

info()    { printf "${C_BLUE}[INFO]${C_RESET}  %s\n" "$*" | tee -a "$LOG_FILE"; }
ok()      { printf "${C_GREEN}[OK]${C_RESET}    %s\n" "$*" | tee -a "$LOG_FILE"; }
warn()    { printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*" | tee -a "$LOG_FILE"; }
err()     { printf "${C_RED}[ERR]${C_RESET}   %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
section() {
    printf "\n${C_BOLD}${C_BLUE}=== %s ===${C_RESET}\n" "$*" | tee -a "$LOG_FILE"
}

confirm() {
    local prompt="${1:-Proceed?}"
    [[ "${ASSUME_YES:-0}" -eq 1 ]] && return 0
    read -rp "$prompt [Y/n] " ans
    [[ -z "$ans" || "$ans" =~ ^[YyJj]$ ]]
}

# =============================================================================
# Flags
# =============================================================================
ASSUME_YES=0
SKIP_PENTEST=0
SKIP_MENU=0
SKIP_BLACKARCH=0
SKIP_AUR=0

usage() {
    cat <<EOF
CachyOS Post-Install — Daily Apps + Pentest Toolkit + KDE Menu

USAGE:
  $0 [OPTIONS]

OPTIONS:
  -y, --yes              Non-interactive (accept all defaults)
  --skip-pentest         Skip pentest tools (daily apps + dev only)
  --skip-blackarch       Skip BlackArch repo + officials
  --skip-aur             Skip AUR packages
  --skip-menu            Skip KDE Application Menu reorganization
  -h, --help             Show this help

WHAT IT INSTALLS:
  Daily apps:    Google Chrome, Joplin, VS Code (MS), Ghostty
  Dev tools:     git, base-devel, python(2+3), nodejs, go, rust, fish
  Shell utils:   eza, bat, fd, ripgrep, fzf, btop, etc.
  Kali basics:   netcat, rlwrap, feroxbuster, gobuster, ffuf, nuclei...
  Pentest:       blackarch-officials (~150 tools)
  AUR pentest:   kerbrute-bin, autorecon-git, certipy-ad, sliver-bin
  Wordlists:     seclists, wordlists (rockyou auto-decompressed)
  KDE Menu:      Pentest Tools/ folder with subcategories

LOG: $LOG_FILE
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)         ASSUME_YES=1 ;;
        --skip-pentest)   SKIP_PENTEST=1 ;;
        --skip-blackarch) SKIP_BLACKARCH=1 ;;
        --skip-aur)       SKIP_AUR=1 ;;
        --skip-menu)      SKIP_MENU=1 ;;
        -h|--help)        usage; exit 0 ;;
        *)                err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# =============================================================================
# Pre-flight
# =============================================================================
preflight() {
    section "Pre-flight checks"

    if ! grep -q "ID=cachyos" /etc/os-release 2>/dev/null && \
       ! grep -q "ID=arch" /etc/os-release 2>/dev/null; then
        warn "Not running on CachyOS or Arch — package names may differ"
        confirm "Continue anyway?" || exit 1
    fi
    ok "Distribution: $(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"

    if ! curl -fsS --max-time 5 https://archlinux.org >/dev/null; then
        err "No network connectivity"
        exit 1
    fi
    ok "Network: reachable"

    local free_gb
    free_gb=$(df --output=avail -BG / | tail -1 | tr -d 'G ')
    if [[ $free_gb -lt 8 ]]; then
        warn "Less than 8GB free on /. Some installs may fail."
        confirm "Continue?" || exit 1
    fi
    ok "Disk space: ${free_gb}G free"

    if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
        warn "Neither yay nor paru found — will install yay"
    else
        ok "AUR helper: $(command -v yay paru 2>/dev/null | head -1)"
    fi
}

# =============================================================================
# 1. System update
# =============================================================================
system_update() {
    section "1. System update"
    if confirm "Run pacman -Syyu now?"; then
        sudo pacman -Syyu --noconfirm
        ok "System updated"
    else
        warn "Skipped"
    fi
}

# =============================================================================
# 2. yay (AUR helper) — install if missing
# =============================================================================
ensure_yay() {
    section "2. Ensure yay (AUR helper)"
    if command -v yay >/dev/null 2>&1; then
        ok "yay already installed"
        return 0
    fi

    info "Installing yay-bin from AUR (bootstrap)"
    sudo pacman -S --needed --noconfirm git base-devel
    local tmp
    tmp=$(mktemp -d)
    git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay"
    (cd "$tmp/yay" && makepkg -si --noconfirm)
    rm -rf "$tmp"
    ok "yay installed"
}

# =============================================================================
# 3. Base development tools
# =============================================================================
install_base_dev() {
    section "3. Base development tools"
    local pkgs=(
        # Core build / VCS
        git base-devel cmake make pkgconf
        curl wget
        unzip zip p7zip
        man-db man-pages
        pacman-contrib

        # Languages / runtimes
        python python-pip
        python2                # for legacy Kali scripts
        nodejs npm
        go
        rust
        ruby

        # Shells & terminals
        fish zsh
        tmux

        # Modern CLI replacements
        eza bat fd ripgrep fzf
        btop htop
        tree
        jq yq
        neofetch fastfetch

        # Editors (CLI)
        neovim vim nano

        # Networking utils
        bind iputils nmap mtr traceroute whois
        openssh openvpn wireguard-tools
        rsync

        # Misc system
        flatpak
        ufw
    )

    info "Packages: ${#pkgs[@]} packages"
    if confirm "Install base dev tools?"; then
        sudo pacman -S --needed --noconfirm "${pkgs[@]}" 2>&1 | tail -10 \
            || warn "Some base packages failed"
    fi
    ok "Base dev tools done"
}

# =============================================================================
# 4. Kali-default tooling (the basics every pentest tutorial assumes)
# =============================================================================
install_kali_basics() {
    section "4. Kali-default basics (netcat, rlwrap, etc.)"
    local pkgs=(
        # Netcat variants
        gnu-netcat                # 'netcat' command
        openbsd-netcat            # 'nc' (preferred for pentest, supports -e)
        socat
        ncat                      # nmap's netcat (most featureful)

        # Shell upgrade utility
        rlwrap                    # arrow-key support in raw shells

        # File transfer / web
        gobuster
        feroxbuster
        ffuf
        wfuzz
        dirsearch
        nikto
        whatweb
        wafw00f

        # Web app
        sqlmap
        nuclei

        # Cracking
        hashcat
        john
        hydra
        medusa
        ncrack

        # SMB / AD / Windows
        smbclient
        impacket                  # python3-impacket on Kali
        responder
        bloodhound

        # Exploitation
        metasploit
        exploitdb                 # provides searchsploit
        sslscan

        # Sniffing
        wireshark-qt
        tcpdump
        bettercap

        # Wireless
        aircrack-ng
        reaver

        # Forensics / steg
        binwalk
        foremost
        steghide
        exiftool

        # Misc
        proxychains-ng
        tor
        torsocks
        snmp                      # snmpwalk, snmpget
    )

    info "Packages: ${#pkgs[@]} essentials"
    if confirm "Install Kali-style basics?"; then
        sudo pacman -S --needed --noconfirm "${pkgs[@]}" 2>&1 | tail -10 \
            || warn "Some packages failed (some may not be in repos yet — fix below)"
    fi
    ok "Kali basics done"
}

# =============================================================================
# 5. BlackArch repository + officials metapackage
# =============================================================================
setup_blackarch() {
    section "5. BlackArch repository"
    if [[ $SKIP_BLACKARCH -eq 1 ]] || [[ $SKIP_PENTEST -eq 1 ]]; then
        warn "Skipped"
        return 0
    fi

    if grep -q "^\[blackarch\]" /etc/pacman.conf 2>/dev/null; then
        ok "BlackArch repo already configured"
    else
        if ! confirm "Add BlackArch pentest repository (~2860 tools available)?"; then
            warn "Skipped BlackArch repo"
            return 0
        fi

        local strap=/tmp/strap.sh
        info "Downloading strap.sh..."
        curl -sSfL -o "$strap" https://blackarch.org/strap.sh
        info "Verifying SHA1..."
        if ! echo "00688950aaf5e5804d2abebb8d3d3ea1d28525ed  $strap" | sha1sum -c; then
            err "SHA1 mismatch! strap.sh may be tampered. Aborting."
            rm -f "$strap"
            return 1
        fi
        chmod +x "$strap"
        sudo "$strap" || warn "strap.sh returned non-zero (continuing)"
        rm -f "$strap"

        if [[ -f /var/lib/pacman/db.lck ]] && ! pgrep -x pacman >/dev/null; then
            warn "Stale pacman lock found; removing"
            sudo rm -f /var/lib/pacman/db.lck
        fi
        sudo pacman -Syy --noconfirm
        ok "BlackArch repo ready"
    fi

    section "5b. blackarch-officials metapackage"
    info "blackarch-officials: ~150 curated essential tools (~3GB)"
    if confirm "Install blackarch-officials?"; then
        sudo pacman -S --needed --noconfirm blackarch-officials 2>&1 | tail -10 \
            || warn "Some packages failed (file conflicts are normal — see log)"
    fi
    ok "BlackArch officials done"

    section "5c. Wordlists"
    if confirm "Install seclists + wordlists?"; then
        sudo pacman -S --needed --noconfirm seclists wordlists fuzzdb 2>&1 | tail -5 \
            || warn "Wordlists install had issues"

        # Auto-decompress rockyou.txt if compressed
        for path in /usr/share/wordlists/rockyou.txt.gz /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt.tar.gz; do
            if [[ -f "$path" ]]; then
                info "Decompressing $path..."
                if [[ "$path" == *.gz ]] && [[ "$path" != *.tar.gz ]]; then
                    sudo gunzip -k "$path" 2>/dev/null || true
                fi
            fi
        done
    fi
    ok "Wordlists done"
}

# =============================================================================
# 6. Daily desktop apps
# =============================================================================
install_daily_apps() {
    section "6. Daily desktop apps"

    info "Installing official-repo apps (Joplin, Ghostty)..."
    sudo pacman -S --needed --noconfirm \
        ghostty \
        2>&1 | tail -5 || warn "Some pacman apps failed"

    if [[ $SKIP_AUR -eq 1 ]]; then
        warn "Skipping AUR apps (Chrome, VS Code, Joplin)"
        return 0
    fi

    info "Installing AUR apps (Chrome, VS Code, Joplin)..."
    yay -S --needed --noconfirm \
        google-chrome \
        visual-studio-code-bin \
        joplin-desktop \
        2>&1 | tail -10 || warn "Some AUR apps failed (re-run if interrupted)"

    ok "Daily apps done"
}

# =============================================================================
# 7. AUR pentest tools
# =============================================================================
install_aur_pentest() {
    section "7. AUR pentest tools"
    if [[ $SKIP_PENTEST -eq 1 ]] || [[ $SKIP_AUR -eq 1 ]]; then
        warn "Skipped"
        return 0
    fi

    local pkgs=(
        kerbrute-bin
        autorecon
        certipy-ad
        sliver-bin
        netexec-git
        pwndbg
        ghidra
        burpsuite
    )

    info "Packages: ${pkgs[*]}"
    if confirm "Install AUR pentest tools (~1-2 GB)?"; then
        yay -S --needed --noconfirm "${pkgs[@]}" 2>&1 | tail -10 \
            || warn "Some AUR pentest tools failed (likely existing-package conflicts)"
    fi
    ok "AUR pentest tools done"
}

# =============================================================================
# 8. Compatibility — Kali-style command symlinks on Arch
# =============================================================================
fix_kali_compatibility() {
    section "8. Kali compatibility symlinks"

    sudo mkdir -p /usr/local/bin

    # impacket-* symlinks (so 'impacket-smbserver' etc. work like on Kali)
    info "Creating impacket-* symlinks..."
    local count=0
    for script in /usr/bin/*.py; do
        [[ -f "$script" ]] || continue
        if grep -q "from impacket\|import impacket" "$script" 2>/dev/null; then
            local name link
            name=$(basename "$script" .py)
            link="/usr/local/bin/impacket-$name"
            if [[ ! -L "$link" ]]; then
                sudo ln -sf "$script" "$link"
                ((count++))
            fi
        fi
    done
    ok "Created $count impacket-* symlinks"

    # crackmapexec → nxc (and vice versa)
    info "Creating crackmapexec/nxc/cme symlinks..."
    if command -v nxc >/dev/null 2>&1 && ! command -v crackmapexec >/dev/null 2>&1; then
        sudo ln -sf "$(command -v nxc)" /usr/local/bin/crackmapexec
        sudo ln -sf "$(command -v nxc)" /usr/local/bin/cme
        ok "crackmapexec, cme → nxc"
    fi
    if command -v crackmapexec >/dev/null 2>&1 && ! command -v nxc >/dev/null 2>&1; then
        sudo ln -sf "$(command -v crackmapexec)" /usr/local/bin/nxc
        ok "nxc → crackmapexec"
    fi

    # enum4linux ↔ enum4linux-ng
    if command -v enum4linux-ng >/dev/null 2>&1 && ! command -v enum4linux >/dev/null 2>&1; then
        sudo ln -sf "$(command -v enum4linux-ng)" /usr/local/bin/enum4linux
        ok "enum4linux → enum4linux-ng"
    fi

    # Permissions: nmap raw socket access without sudo
    if command -v nmap >/dev/null 2>&1; then
        info "Granting nmap raw-socket capability (no sudo needed for SYN scan)"
        sudo setcap cap_net_raw,cap_net_admin,cap_net_bind_service+eip "$(command -v nmap)" || true
    fi

    # Wireshark group for live capture
    if command -v wireshark >/dev/null 2>&1; then
        sudo groupadd -f wireshark
        sudo usermod -aG wireshark "$USER"
        info "Added $USER to wireshark group (logout/login to take effect)"
    fi

    ok "Compatibility symlinks done"
}

# =============================================================================
# 9. KDE Application Menu — BlackArch-style folders
# =============================================================================
setup_kde_menu() {
    section "9. KDE Application Menu — Pentest folders"
    if [[ $SKIP_MENU -eq 1 ]] || [[ $SKIP_PENTEST -eq 1 ]]; then
        warn "Skipped"
        return 0
    fi

    if ! command -v plasmashell >/dev/null 2>&1; then
        warn "Not running KDE Plasma — skipping menu setup"
        return 0
    fi

    local menu_dir="$HOME/.config/menus"
    local desktop_dir="$HOME/.local/share/desktop-directories"
    local apps_dir="$HOME/.local/share/applications"

    mkdir -p "$menu_dir" "$desktop_dir" "$apps_dir"

    # --- Create directory entries ---
    info "Creating KDE category directories..."
    declare -A categories=(
        [Pentest-Tools]="Pentest Tools|preferences-desktop-cryptography"
        [Pentest-Recon]="Recon|system-search"
        [Pentest-Scanner]="Scanner|edit-find"
        [Pentest-Web]="Web Apps|applications-internet"
        [Pentest-Cracker]="Crackers|dialog-password"
        [Pentest-Wireless]="Wireless|network-wireless"
        [Pentest-Exploit]="Exploitation|applications-debugging"
        [Pentest-PostExploit]="Post-Exploitation|system-run"
        [Pentest-AD]="Active Directory|preferences-system-network"
        [Pentest-Forensic]="Forensics|drive-removable-media"
        [Pentest-Reverse]="Reverse Engineering|applications-development"
        [Pentest-Sniffer]="Sniffers"
    )

    for key in "${!categories[@]}"; do
        local val="${categories[$key]}"
        local name="${val%%|*}"
        local icon="${val##*|}"
        [[ "$icon" == "$name" ]] && icon="folder"

        cat > "$desktop_dir/${key}.directory" <<EOF
[Desktop Entry]
Version=1.0
Type=Directory
Name=$name
Icon=$icon
EOF
    done

    # --- Build the .menu XML ---
    info "Building Pentest-Tools.menu..."
    cat > "$menu_dir/applications-merged-pentest.menu" <<'MENU_EOF'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
<Menu>
  <Name>Applications</Name>

  <Menu>
    <Name>Pentest Tools</Name>
    <Directory>Pentest-Tools.directory</Directory>

    <Menu>
      <Name>Recon</Name>
      <Directory>Pentest-Recon.directory</Directory>
      <Include>
        <Or>
          <Filename>org.kde.nmap.desktop</Filename>
          <Filename>nmap.desktop</Filename>
          <Filename>zenmap.desktop</Filename>
          <Filename>amass.desktop</Filename>
          <Filename>masscan.desktop</Filename>
          <Filename>autorecon.desktop</Filename>
          <Filename>theharvester.desktop</Filename>
          <Filename>recon-ng.desktop</Filename>
          <Filename>dnsrecon.desktop</Filename>
          <Filename>fierce.desktop</Filename>
          <Filename>whatweb.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Scanner</Name>
      <Directory>Pentest-Scanner.directory</Directory>
      <Include>
        <Or>
          <Filename>nikto.desktop</Filename>
          <Filename>wapiti.desktop</Filename>
          <Filename>nuclei.desktop</Filename>
          <Filename>sslscan.desktop</Filename>
          <Filename>testssl.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Web Apps</Name>
      <Directory>Pentest-Web.directory</Directory>
      <Include>
        <Or>
          <Filename>burpsuite.desktop</Filename>
          <Filename>burpsuite-pro.desktop</Filename>
          <Filename>org.zaproxy.ZAP.desktop</Filename>
          <Filename>zaproxy.desktop</Filename>
          <Filename>sqlmap.desktop</Filename>
          <Filename>gobuster.desktop</Filename>
          <Filename>feroxbuster.desktop</Filename>
          <Filename>ffuf.desktop</Filename>
          <Filename>wfuzz.desktop</Filename>
          <Filename>dirsearch.desktop</Filename>
          <Filename>caido.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Crackers</Name>
      <Directory>Pentest-Cracker.directory</Directory>
      <Include>
        <Or>
          <Filename>hashcat.desktop</Filename>
          <Filename>john.desktop</Filename>
          <Filename>hydra.desktop</Filename>
          <Filename>medusa.desktop</Filename>
          <Filename>ncrack.desktop</Filename>
          <Filename>cewl.desktop</Filename>
          <Filename>kerbrute.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Wireless</Name>
      <Directory>Pentest-Wireless.directory</Directory>
      <Include>
        <Or>
          <Filename>aircrack-ng.desktop</Filename>
          <Filename>airodump-ng.desktop</Filename>
          <Filename>reaver.desktop</Filename>
          <Filename>wifite.desktop</Filename>
          <Filename>kismet.desktop</Filename>
          <Filename>bettercap.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Exploitation</Name>
      <Directory>Pentest-Exploit.directory</Directory>
      <Include>
        <Or>
          <Filename>metasploit.desktop</Filename>
          <Filename>msfconsole.desktop</Filename>
          <Filename>searchsploit.desktop</Filename>
          <Filename>set.desktop</Filename>
          <Filename>beef.desktop</Filename>
          <Filename>sliver.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Post-Exploitation</Name>
      <Directory>Pentest-PostExploit.directory</Directory>
      <Include>
        <Or>
          <Filename>linpeas.desktop</Filename>
          <Filename>winpeas.desktop</Filename>
          <Filename>powersploit.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Active Directory</Name>
      <Directory>Pentest-AD.directory</Directory>
      <Include>
        <Or>
          <Filename>bloodhound.desktop</Filename>
          <Filename>impacket.desktop</Filename>
          <Filename>responder.desktop</Filename>
          <Filename>crackmapexec.desktop</Filename>
          <Filename>netexec.desktop</Filename>
          <Filename>nxc.desktop</Filename>
          <Filename>certipy.desktop</Filename>
          <Filename>kerbrute.desktop</Filename>
          <Filename>evil-winrm.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Forensics</Name>
      <Directory>Pentest-Forensic.directory</Directory>
      <Include>
        <Or>
          <Filename>autopsy.desktop</Filename>
          <Filename>volatility.desktop</Filename>
          <Filename>binwalk.desktop</Filename>
          <Filename>foremost.desktop</Filename>
          <Filename>exiftool.desktop</Filename>
          <Filename>steghide.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Reverse Engineering</Name>
      <Directory>Pentest-Reverse.directory</Directory>
      <Include>
        <Or>
          <Filename>ghidra.desktop</Filename>
          <Filename>radare2.desktop</Filename>
          <Filename>org.cutter.cutter.desktop</Filename>
          <Filename>cutter.desktop</Filename>
          <Filename>org.pwndbg.pwndbg.desktop</Filename>
          <Filename>pwndbg.desktop</Filename>
        </Or>
      </Include>
    </Menu>

    <Menu>
      <Name>Sniffers</Name>
      <Directory>Pentest-Sniffer.directory</Directory>
      <Include>
        <Or>
          <Filename>org.wireshark.Wireshark.desktop</Filename>
          <Filename>wireshark.desktop</Filename>
          <Filename>tcpdump.desktop</Filename>
          <Filename>ettercap.desktop</Filename>
          <Filename>bettercap.desktop</Filename>
          <Filename>mitmproxy.desktop</Filename>
        </Or>
      </Include>
    </Menu>

  </Menu>
</Menu>
MENU_EOF

    # --- Generate .desktop entries for CLI tools that don't have one ---
    info "Generating .desktop entries for CLI tools..."
    declare -A cli_tools=(
        [nmap]="Nmap|edit-find|nmap"
        [sqlmap]="sqlmap|edit-find|sqlmap"
        [gobuster]="Gobuster|edit-find|gobuster"
        [feroxbuster]="Feroxbuster|edit-find|feroxbuster"
        [ffuf]="ffuf|edit-find|ffuf"
        [nuclei]="Nuclei|edit-find|nuclei"
        [hydra]="Hydra|dialog-password|hydra"
        [john]="John the Ripper|dialog-password|john --help; read"
        [hashcat]="Hashcat|dialog-password|hashcat -h; read"
        [ncrack]="Ncrack|dialog-password|ncrack"
        [searchsploit]="SearchSploit|edit-find|searchsploit"
        [msfconsole]="Metasploit Console|applications-debugging|msfconsole"
        [responder]="Responder|preferences-system-network|sudo responder -h; read"
        [impacket-smbserver]="Impacket SMB Server|preferences-system-network|impacket-smbserver -h; read"
        [crackmapexec]="CrackMapExec / NetExec|preferences-system-network|nxc -h; read"
        [bloodhound]="BloodHound|preferences-system-network|bloodhound"
        [aircrack-ng]="Aircrack-ng|network-wireless|aircrack-ng --help; read"
        [bettercap]="Bettercap|network-wireless|sudo bettercap"
        [kerbrute]="Kerbrute|preferences-system-network|kerbrute"
        [autorecon]="AutoRecon|system-search|autorecon"
        [linpeas]="linPEAS|system-run|linpeas"
        [winpeas]="winPEAS|system-run|winpeas"
        [proxychains4]="ProxyChains|preferences-system-network|proxychains4 -h; read"
        [evil-winrm]="Evil-WinRM|preferences-system-network|evil-winrm"
    )

    for cmd in "${!cli_tools[@]}"; do
        local val="${cli_tools[$cmd]}"
        local name="${val%%|*}"
        local rest="${val#*|}"
        local icon="${rest%%|*}"
        local exec_line="${rest#*|}"

        # Only generate if command exists
        if ! command -v "$cmd" >/dev/null 2>&1; then continue; fi

        cat > "$apps_dir/${cmd}.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$name (CLI)
Exec=ghostty -e bash -c "$exec_line"
Icon=$icon
Terminal=false
Categories=Pentesting;Security;
EOF
    done
    ok "Generated $(ls "$apps_dir"/*.desktop 2>/dev/null | wc -l) .desktop files"

    # --- Refresh KDE menu cache ---
    info "Refreshing KDE menu cache..."
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 --noincremental 2>/dev/null || true
    elif command -v kbuildsycoca5 >/dev/null 2>&1; then
        kbuildsycoca5 --noincremental 2>/dev/null || true
    fi
    update-desktop-database "$apps_dir" 2>/dev/null || true

    ok "KDE Pentest Tools folder created"
    info "It may take 30-60s to appear; logout/login if you don't see it"
}

# =============================================================================
# 10. Final summary
# =============================================================================
final_summary() {
    section "Setup complete"
    cat <<EOF

  ${C_GREEN}✓${C_RESET} Daily apps:    Chrome, Joplin, VS Code, Ghostty
  ${C_GREEN}✓${C_RESET} Dev tools:     git, python, node, go, rust, fish, zsh
  ${C_GREEN}✓${C_RESET} CLI utilities: eza, bat, fd, ripgrep, fzf, btop
  ${C_GREEN}✓${C_RESET} Kali basics:   netcat, rlwrap, gobuster, ffuf, hashcat, etc.
EOF

    [[ $SKIP_BLACKARCH -eq 0 && $SKIP_PENTEST -eq 0 ]] && cat <<EOF
  ${C_GREEN}✓${C_RESET} BlackArch:     repo + officials metapackage
  ${C_GREEN}✓${C_RESET} Wordlists:     seclists, wordlists, fuzzdb
EOF

    [[ $SKIP_AUR -eq 0 && $SKIP_PENTEST -eq 0 ]] && cat <<EOF
  ${C_GREEN}✓${C_RESET} AUR pentest:   kerbrute, autorecon, certipy, sliver, netexec, ghidra, burpsuite
EOF

    [[ $SKIP_MENU -eq 0 && $SKIP_PENTEST -eq 0 ]] && cat <<EOF
  ${C_GREEN}✓${C_RESET} KDE Menu:      Pentest Tools/ folder with subcategories
EOF

    cat <<EOF

  ${C_YELLOW}Next steps:${C_RESET}
    1. ${C_BOLD}Logout / login${C_RESET} for wireshark group + KDE menu refresh
    2. Test:  ${C_BOLD}nmap -sV scanme.nmap.org${C_RESET}     (no sudo needed!)
    3. Open KDE Application Menu — look for ${C_BOLD}'Pentest Tools'${C_RESET}
    4. If menu doesn't show: kbuildsycoca6 --noincremental

  ${C_BLUE}Log file:${C_RESET} $LOG_FILE

EOF
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo "=============================================================="
    echo " CachyOS Post-Install — v$SCRIPT_VERSION"
    echo " Log: $LOG_FILE"
    echo "=============================================================="

    preflight
    system_update
    ensure_yay
    install_base_dev
    install_kali_basics
    setup_blackarch
    install_daily_apps
    install_aur_pentest
    fix_kali_compatibility
    setup_kde_menu
    final_summary
}

main "$@"
