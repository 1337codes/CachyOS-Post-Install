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
readonly SCRIPT_VERSION="2.1.1-oscp"
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
        # python2 — REMOVED: EOL since 2020, broken on modern Arch (no openssl-1.1)
        # If you need it for legacy OSCP scripts: yay -S python2-bin
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
    # Only include packages that exist in CachyOS/Arch main repos.
    # BlackArch-only tools are installed in step 5 (after BlackArch repo is added).
    local pkgs=(
        # Netcat variants
        gnu-netcat                # 'netcat' command
        openbsd-netcat            # 'nc' (preferred for pentest, supports -e)
        socat
        ncat                      # nmap's netcat (most featureful)

        # Shell upgrade utility
        rlwrap                    # arrow-key support in raw shells
        expect                    # for unbuffer / automation

        # Web fuzzing / discovery
        gobuster
        feroxbuster
        ffuf
        wfuzz
        dirsearch
        nikto
        whatweb
        wafw00f

        # Web app testing
        sqlmap
        nuclei

        # Cracking
        hashcat
        john
        hydra
        medusa
        ncrack
        cewl                      # custom wordlists from web

        # SMB / AD / Windows
        smbclient
        impacket                  # python3-impacket on Kali
        responder
        # bloodhound — moved to BlackArch (step 5)
        enum4linux-ng             # 'enum4linux' on Kali; symlinked later
        # smbmap — moved to BlackArch (step 5)
        cifs-utils

        # Exploitation
        metasploit
        sslscan
        # exploitdb — provides searchsploit; moved to BlackArch (more reliable there)

        # Sniffing
        wireshark-qt
        tcpdump
        bettercap
        # ettercap — sometimes broken in Arch repos; fallback to BlackArch

        # Wireless
        aircrack-ng
        reaver
        # wifite — moved to BlackArch (not always in main repos)

        # Forensics / steg
        binwalk
        foremost
        # steghide — moved to BlackArch
        perl-image-exiftool       # 'exiftool' on Kali; provides /usr/bin/exiftool

        # Misc
        proxychains-ng
        tor
        torsocks
        net-snmp                  # snmpwalk, snmpget — 'snmp' on Kali
        # onesixtyone — moved to BlackArch
        # snmpcheck — moved to BlackArch

        # Network mapping / recon
        masscan
        whois
        bind                      # provides dig, nslookup
        traceroute
        mtr

        # Misc helpers
        cmatrix                   # because hacker
        figlet                    # ascii banners
        toilet
        flameshot                 # screenshot tool (multi-monitor support)
        keepassxc                 # password manager (for engagement creds)
        gimp                      # image editing for screenshots
        kdenlive                  # video editing (for PoCs)
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

    section "5c. Wordlists (Kali-compatible paths)"
    if confirm "Install seclists + wordlists + dirb wordlists?"; then
        sudo pacman -S --needed --noconfirm seclists wordlists fuzzdb dirb 2>&1 | tail -5 \
            || warn "Some wordlists install failed"

        # Auto-decompress rockyou.txt if compressed
        for path in /usr/share/wordlists/rockyou.txt.gz /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt.tar.gz; do
            if [[ -f "$path" ]]; then
                info "Decompressing $path..."
                if [[ "$path" == *.gz ]] && [[ "$path" != *.tar.gz ]]; then
                    sudo gunzip -k "$path" 2>/dev/null || true
                fi
            fi
        done

        # === Kali-compatible wordlist paths ===
        # On Kali, all wordlists are under /usr/share/wordlists/.
        # On Arch, they're scattered across /usr/share/{seclists,dirb,wfuzz,...}
        # Create symlinks so Kali tutorials "just work".
        info "Setting up Kali-compatible wordlist paths in /usr/share/wordlists/..."
        sudo mkdir -p /usr/share/wordlists

        # SecLists - the most important one, all OSCP guides use it
        if [[ -d /usr/share/seclists && ! -e /usr/share/wordlists/seclists ]]; then
            sudo ln -sfn /usr/share/seclists /usr/share/wordlists/seclists
            sudo ln -sfn /usr/share/seclists /usr/share/wordlists/SecLists  # case variant
            ok "Symlink: /usr/share/wordlists/seclists → /usr/share/seclists"
        fi

        # dirb wordlists (provides /usr/share/wordlists/dirb on Kali)
        if [[ -d /usr/share/dirb/wordlists && ! -e /usr/share/wordlists/dirb ]]; then
            sudo ln -sfn /usr/share/dirb/wordlists /usr/share/wordlists/dirb
            ok "Symlink: /usr/share/wordlists/dirb → /usr/share/dirb/wordlists"
        fi

        # dirbuster wordlists (commonly referenced in OSCP)
        # On Kali: /usr/share/wordlists/dirbuster -> /usr/share/dirbuster/wordlists
        if [[ -d /usr/share/dirbuster/wordlists && ! -e /usr/share/wordlists/dirbuster ]]; then
            sudo ln -sfn /usr/share/dirbuster/wordlists /usr/share/wordlists/dirbuster
            ok "Symlink: /usr/share/wordlists/dirbuster → /usr/share/dirbuster/wordlists"
        elif [[ -d /usr/share/seclists/Discovery/Web-Content && ! -e /usr/share/wordlists/dirbuster ]]; then
            # Fallback: symlink to seclists Web-Content (functionally similar)
            sudo ln -sfn /usr/share/seclists/Discovery/Web-Content /usr/share/wordlists/dirbuster
            ok "Symlink: /usr/share/wordlists/dirbuster → seclists/Discovery/Web-Content (fallback)"
        fi

        # fuzzdb
        if [[ -d /usr/share/fuzzdb && ! -e /usr/share/wordlists/fuzzdb ]]; then
            sudo ln -sfn /usr/share/fuzzdb /usr/share/wordlists/fuzzdb
            ok "Symlink: /usr/share/wordlists/fuzzdb → /usr/share/fuzzdb"
        fi

        # Common shortcut: /usr/share/wordlists/rockyou.txt should always exist
        # (if we got it from seclists, link it to top level)
        local rockyou_src
        for cand in \
            /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt \
            /usr/share/wordlists/rockyou.txt \
            /usr/share/wordlists/seclists/Passwords/Leaked-Databases/rockyou.txt; do
            if [[ -f "$cand" ]]; then
                rockyou_src="$cand"
                break
            fi
        done
        if [[ -n "${rockyou_src:-}" && ! -e /usr/share/wordlists/rockyou.txt ]]; then
            sudo ln -sf "$rockyou_src" /usr/share/wordlists/rockyou.txt
            ok "Symlink: /usr/share/wordlists/rockyou.txt → $rockyou_src"
        fi

        # Show final layout
        info "Final wordlists layout:"
        ls -la /usr/share/wordlists/ 2>/dev/null | grep -E "^[ld]" | head -15 | tee -a "$LOG_FILE"
    fi
    ok "Wordlists done"

    section "5d. BlackArch-exclusive tools"
    # These tools weren't installable in step 4 because they're only in BlackArch.
    # Now that BlackArch repo is added, install them here.
    if [[ $SKIP_BLACKARCH -eq 0 ]]; then
        local blackarch_only=(
            bloodhound                # AD enumeration
            smbmap                    # SMB share mapping
            steghide                  # Steganography
            onesixtyone               # SNMP community brute
            snmpcheck                 # SNMP enum
            wifite2                   # Wireless attack automation (newer fork of wifite)
            ettercap                  # MITM (when not in main repos)
            commix                    # Command injection
            xsser                     # XSS framework
            gospider                  # Web spider
            exploitdb                 # searchsploit (more reliable from blackarch)
            evil-winrm                # WinRM shell (often only here)
            theharvester              # OSINT email harvester
            recon-ng                  # Recon framework
            dnsrecon                  # DNS recon
            fierce                    # Domain scanner
            wpscan                    # WordPress scanner
            joomscan                  # Joomla scanner
            droopescan                # CMS scanner
            arjun                     # HTTP parameter discovery
            crlfuzz                   # CRLF injection
            shodan                    # Shodan CLI
            seclists                  # ensure (was earlier but cheap to re-confirm)
        )

        info "Installing BlackArch-exclusive tools (${#blackarch_only[@]} packages)..."
        if confirm "Install these BlackArch tools?"; then
            sudo pacman -S --needed --noconfirm "${blackarch_only[@]}" 2>&1 | tail -10 \
                || warn "Some BlackArch tools failed (will continue)"
        fi
        ok "BlackArch-exclusive tools done"
    else
        warn "Skipped (--skip-blackarch)"
    fi
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
    section "7. AUR pentest tools (OSCP-essentials)"
    if [[ $SKIP_PENTEST -eq 1 ]] || [[ $SKIP_AUR -eq 1 ]]; then
        warn "Skipped"
        return 0
    fi

    # ==[ Active Directory & Windows ]==
    local ad_pkgs=(
        kerbrute-bin              # Kerberos pre-auth username enum + spray
        certipy-ad                # AD CS abuse (ESC1-ESC15)
        netexec-git               # NetExec (nxc) - successor to crackmapexec
        evil-winrm                # WinRM shell
        impacket                  # impacket scripts (already in pacman, listed for clarity)
        bloodhound-python-git     # Python BloodHound collector
        rusthound                 # Rust BloodHound (faster)
        adidnsdump-git            # AD DNS dumping
        powerview-git             # PowerView ported to Python
        pywerview                 # alternative PowerView
        ldapdomaindump            # LDAP info dump
        donpapi-git               # DPAPI dumping
    )

    # ==[ Tunneling & Pivoting ]==
    local tunnel_pkgs=(
        ligolo-ng                 # ⭐ THE pivoting tool for OSCP
        chisel                    # HTTP-tunneled TCP
        sshuttle                  # poor man's VPN over SSH
        gost                      # advanced tunneling
        sshpass                   # automated ssh
    )

    # ==[ Web App Testing ]==
    local web_pkgs=(
        burpsuite                 # community edition (Pro = manual install)
        zaproxy                   # OWASP ZAP
        caido-bin                 # modern Burp alternative
        amass                     # subdomain enum
        subfinder                 # subdomain enum (ProjectDiscovery)
        httpx-bin                 # http probe (NOT python httpx!)
        katana-bin                # web crawler
        dalfox                    # XSS scanner
        knock                     # subdomain enum
        photon-git                # OSINT crawler
    )

    # ==[ Exploitation & C2 ]==
    local exploit_pkgs=(
        sliver-bin                # Modern C2 framework
        pwncat-cs                 # netcat replacement w/ post-exploit features
        revshells                 # generate reverse shells
        msfpc                     # MSF payload generator
    )

    # ==[ Recon & Enumeration ]==
    local recon_pkgs=(
        autorecon                 # automated recon (huge time saver for OSCP)
        rustscan                  # super fast port scanner
        nuclei-templates          # nuclei templates
        gowitness                 # screenshot websites
        eyewitness                # alternative screenshot tool
        dnsx-bin                  # fast DNS toolkit
        nmap-vulners              # nmap vuln scripts
    )

    # ==[ Privesc Helpers ]==
    local privesc_pkgs=(
        peass-ng                  # linpeas + winpeas
        linux-exploit-suggester   # linux privesc
        windows-exploit-suggester # windows privesc
        pspy-bin                  # process spy (no root)
    )

    # ==[ Cracking & Hashing ]==
    local crack_pkgs=(
        crackmapexec              # legacy cme (some still prefer over nxc)
        hashid                    # hash type identifier
        name-that-hash            # alternative hash identifier
        hash-identifier
        ophcrack                  # rainbow tables
        hcxtools                  # hashcat helper for wifi
        hcxdumptool
    )

    # ==[ Reverse Engineering ]==
    local re_pkgs=(
        ghidra                    # NSA's RE tool
        cutter                    # radare2 GUI
        pwndbg                    # gdb plugin for exploit dev
        gef                       # alternative gdb plugin
        peda                      # alternative gdb plugin
        binaryninja-free          # free version of Binary Ninja
    )

    # ==[ Misc OSCP utilities ]==
    local misc_pkgs=(
        seclists                  # already in pacman but ensure
        payloadsallthethings-git  # PayloadsAllTheThings
        rockyou                   # rockyou wordlist (if not in seclists)
        oscp-pwk-scripts          # OSCP-flavored helpers (if available)
        sherlock                  # username OSINT
        holehe                    # email OSINT
        gitleaks                  # secrets scanner
        trufflehog-bin            # secrets scanner
    )

    # Merge all
    local all_pkgs=(
        "${ad_pkgs[@]}"
        "${tunnel_pkgs[@]}"
        "${web_pkgs[@]}"
        "${exploit_pkgs[@]}"
        "${recon_pkgs[@]}"
        "${privesc_pkgs[@]}"
        "${crack_pkgs[@]}"
        "${re_pkgs[@]}"
        "${misc_pkgs[@]}"
    )

    info "Categories overview:"
    info "  Active Directory:  ${#ad_pkgs[@]} tools  (kerbrute, certipy, nxc, BloodHound, ...)"
    info "  Tunneling/Pivot:   ${#tunnel_pkgs[@]} tools  (ligolo-ng, chisel, sshuttle, ...)"
    info "  Web Testing:       ${#web_pkgs[@]} tools  (Burp, ZAP, amass, subfinder, ...)"
    info "  Exploitation/C2:   ${#exploit_pkgs[@]} tools  (sliver, pwncat-cs, ...)"
    info "  Recon/Enum:        ${#recon_pkgs[@]} tools  (autorecon, rustscan, gowitness, ...)"
    info "  Privesc Helpers:   ${#privesc_pkgs[@]} tools  (linpeas, pspy, ...)"
    info "  Cracking:          ${#crack_pkgs[@]} tools  (cme legacy, hashid, hcxtools, ...)"
    info "  Reverse Eng.:      ${#re_pkgs[@]} tools  (ghidra, cutter, pwndbg, gef, peda, ...)"
    info "  Misc:              ${#misc_pkgs[@]} tools  (PayloadsAllTheThings, sherlock, ...)"
    info "Total: ${#all_pkgs[@]} AUR packages (~3-5 GB)"

    if confirm "Install ALL AUR pentest tools (recommended for OSCP)?"; then
        # Install in batches per category - some may fail without breaking everything
        info "Installing AD tools..."
        yay -S --needed --noconfirm "${ad_pkgs[@]}" 2>&1 | tail -5 || warn "Some AD pkgs failed"

        info "Installing tunneling tools..."
        yay -S --needed --noconfirm "${tunnel_pkgs[@]}" 2>&1 | tail -5 || warn "Some tunnel pkgs failed"

        info "Installing web testing tools..."
        yay -S --needed --noconfirm "${web_pkgs[@]}" 2>&1 | tail -5 || warn "Some web pkgs failed"

        info "Installing exploitation/C2..."
        yay -S --needed --noconfirm "${exploit_pkgs[@]}" 2>&1 | tail -5 || warn "Some exploit pkgs failed"

        info "Installing recon tools..."
        yay -S --needed --noconfirm "${recon_pkgs[@]}" 2>&1 | tail -5 || warn "Some recon pkgs failed"

        info "Installing privesc helpers..."
        yay -S --needed --noconfirm "${privesc_pkgs[@]}" 2>&1 | tail -5 || warn "Some privesc pkgs failed"

        info "Installing cracking tools..."
        yay -S --needed --noconfirm "${crack_pkgs[@]}" 2>&1 | tail -5 || warn "Some crack pkgs failed"

        info "Installing reverse engineering tools..."
        yay -S --needed --noconfirm "${re_pkgs[@]}" 2>&1 | tail -5 || warn "Some RE pkgs failed"

        info "Installing misc utilities..."
        yay -S --needed --noconfirm "${misc_pkgs[@]}" 2>&1 | tail -5 || warn "Some misc pkgs failed"
    elif confirm "Install only essentials (AD + tunneling + autorecon + ligolo-ng)?"; then
        local essentials=(
            kerbrute-bin certipy-ad netexec-git evil-winrm
            ligolo-ng chisel
            autorecon rustscan
            peass-ng pwncat-cs
        )
        yay -S --needed --noconfirm "${essentials[@]}" 2>&1 | tail -10 \
            || warn "Some essentials failed"
    fi
    ok "AUR pentest tools done"
}

# =============================================================================
# 7b. Manual downloads — tools that aren't in repos
# =============================================================================
install_manual_tools() {
    section "7b. Manual tool downloads (not in AUR/repos)"
    if [[ $SKIP_PENTEST -eq 1 ]]; then
        warn "Skipped"
        return 0
    fi

    local tools_dir="$HOME/.local/share/pentest-tools"
    mkdir -p "$tools_dir"

    if ! confirm "Download manual tools to $tools_dir?"; then
        warn "Skipped"
        return 0
    fi

    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"

    # Ensure ~/.local/bin is in PATH
    if ! echo "$PATH" | grep -q "$bin_dir"; then
        info "Adding $bin_dir to PATH..."
        if [[ -f "$HOME/.config/fish/config.fish" ]]; then
            echo "set -gx PATH \$HOME/.local/bin \$PATH" >> "$HOME/.config/fish/config.fish"
        fi
        if [[ -f "$HOME/.bashrc" ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        fi
        if [[ -f "$HOME/.zshrc" ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
        fi
    fi

    # ==[ PEASS-ng (linpeas + winpeas) ]==
    info "Downloading PEASS-ng (linpeas + winpeas)..."
    local peass_dir="$tools_dir/PEASS-ng"
    if [[ ! -d "$peass_dir" ]]; then
        git clone --depth=1 https://github.com/peass-ng/PEASS-ng.git "$peass_dir"
    else
        (cd "$peass_dir" && git pull --quiet) || warn "PEASS-ng pull failed"
    fi

    # ==[ PowerSploit ]==
    info "Downloading PowerSploit..."
    local ps_dir="$tools_dir/PowerSploit"
    if [[ ! -d "$ps_dir" ]]; then
        git clone --depth=1 https://github.com/PowerShellMafia/PowerSploit.git "$ps_dir"
    else
        (cd "$ps_dir" && git pull --quiet) || warn "PowerSploit pull failed"
    fi

    # ==[ PayloadsAllTheThings ]==
    info "Downloading PayloadsAllTheThings (slow, ~500MB)..."
    local pat_dir="$tools_dir/PayloadsAllTheThings"
    if [[ ! -d "$pat_dir" ]]; then
        git clone --depth=1 https://github.com/swisskyrepo/PayloadsAllTheThings.git "$pat_dir" \
            || warn "PayloadsAllTheThings clone failed (try later)"
    else
        (cd "$pat_dir" && git pull --quiet) || warn "PayloadsAllTheThings pull failed"
    fi

    # ==[ HackTricks (offline reference) ]==
    info "Downloading HackTricks book..."
    local ht_dir="$tools_dir/hacktricks"
    if [[ ! -d "$ht_dir" ]]; then
        git clone --depth=1 https://github.com/HackTricks-wiki/hacktricks.git "$ht_dir" \
            || warn "HackTricks clone failed"
    fi

    # ==[ Mimikatz binary ]==
    info "Downloading Mimikatz..."
    local mimi_dir="$tools_dir/mimikatz"
    if [[ ! -f "$mimi_dir/mimikatz.exe" ]]; then
        mkdir -p "$mimi_dir"
        local mimi_url
        mimi_url=$(curl -fsSL https://api.github.com/repos/gentilkiwi/mimikatz/releases/latest \
                   | grep "browser_download_url.*mimikatz_trunk.zip" \
                   | head -1 | cut -d'"' -f4)
        if [[ -n "$mimi_url" ]]; then
            curl -fsSL -o "$mimi_dir/mimikatz.zip" "$mimi_url"
            (cd "$mimi_dir" && unzip -q -o mimikatz.zip && rm mimikatz.zip)
            ok "Mimikatz downloaded"
        else
            warn "Could not fetch Mimikatz URL"
        fi
    fi

    # ==[ Chisel binaries (linux + windows) ]==
    info "Ensuring Chisel binaries (linux + windows)..."
    local chisel_dir="$tools_dir/chisel"
    mkdir -p "$chisel_dir"
    if [[ ! -f "$chisel_dir/chisel_linux_amd64" ]]; then
        local chisel_ver
        chisel_ver=$(curl -fsSL https://api.github.com/repos/jpillora/chisel/releases/latest \
                     | grep tag_name | cut -d'"' -f4 | tr -d 'v')
        if [[ -n "$chisel_ver" ]]; then
            curl -fsSL -o /tmp/chisel-linux.gz \
                "https://github.com/jpillora/chisel/releases/download/v${chisel_ver}/chisel_${chisel_ver}_linux_amd64.gz"
            curl -fsSL -o /tmp/chisel-windows.gz \
                "https://github.com/jpillora/chisel/releases/download/v${chisel_ver}/chisel_${chisel_ver}_windows_amd64.gz"
            gunzip -c /tmp/chisel-linux.gz > "$chisel_dir/chisel_linux_amd64"
            gunzip -c /tmp/chisel-windows.gz > "$chisel_dir/chisel_windows_amd64.exe"
            chmod +x "$chisel_dir/chisel_linux_amd64"
            rm /tmp/chisel-linux.gz /tmp/chisel-windows.gz
            ok "Chisel v$chisel_ver downloaded (linux + windows)"
        fi
    fi

    # ==[ Ligolo-ng binaries (proxy + agent for windows) ]==
    info "Ensuring Ligolo-ng binaries..."
    local ligolo_dir="$tools_dir/ligolo-ng"
    mkdir -p "$ligolo_dir"
    if [[ ! -f "$ligolo_dir/agent.exe" ]]; then
        local ligolo_ver
        ligolo_ver=$(curl -fsSL https://api.github.com/repos/Nicocha30/ligolo-ng/releases/latest \
                     | grep tag_name | cut -d'"' -f4)
        if [[ -n "$ligolo_ver" ]]; then
            local v="${ligolo_ver#v}"
            # Linux proxy
            curl -fsSL -o /tmp/ligolo-proxy.tar.gz \
                "https://github.com/Nicocha30/ligolo-ng/releases/download/${ligolo_ver}/ligolo-ng_proxy_${v}_linux_amd64.tar.gz"
            tar xzf /tmp/ligolo-proxy.tar.gz -C "$ligolo_dir/" proxy
            mv "$ligolo_dir/proxy" "$ligolo_dir/proxy_linux"
            # Windows agent
            curl -fsSL -o /tmp/ligolo-agent.zip \
                "https://github.com/Nicocha30/ligolo-ng/releases/download/${ligolo_ver}/ligolo-ng_agent_${v}_windows_amd64.zip"
            (cd "$ligolo_dir" && unzip -q -o /tmp/ligolo-agent.zip)
            chmod +x "$ligolo_dir/proxy_linux"
            rm /tmp/ligolo-proxy.tar.gz /tmp/ligolo-agent.zip
            ok "Ligolo-ng ${ligolo_ver} downloaded (proxy + agent)"
        fi
    fi

    # ==[ Static binaries directory for upload to targets ]==
    info "Building static binaries directory for transfer..."
    local static_dir="$tools_dir/static-bins"
    mkdir -p "$static_dir/linux" "$static_dir/windows"

    # Static nmap (for transferring to targets)
    if [[ ! -f "$static_dir/linux/nmap" ]]; then
        curl -fsSL -o "$static_dir/linux/nmap" \
            "https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/nmap" 2>/dev/null \
            && chmod +x "$static_dir/linux/nmap" \
            && ok "Static nmap downloaded"
    fi

    # Static socat
    if [[ ! -f "$static_dir/linux/socat" ]]; then
        curl -fsSL -o "$static_dir/linux/socat" \
            "https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/socat" 2>/dev/null \
            && chmod +x "$static_dir/linux/socat" \
            && ok "Static socat downloaded"
    fi

    # ==[ Symlink convenience: pentest-tools alias ]==
    info "Creating shell aliases for tools dir..."
    cat > "$HOME/.config/pentest-tools-aliases.sh" <<EOF
# Convenience env vars for pentest tools
export PENTEST_TOOLS="$tools_dir"
export PEASS="$peass_dir"
export PAYLOADS="$pat_dir"
export STATIC_BINS="$static_dir"
export LIGOLO="$ligolo_dir"
export CHISEL="$chisel_dir"

# Quick access aliases
alias linpeas-here='cp \$PEASS/linPEAS/linpeas.sh .'
alias winpeas-here='cp \$PEASS/winPEAS/winPEASexe/winPEAS/bin/x64/Release/winPEASx64.exe .'
alias serve-tools='cd \$PENTEST_TOOLS && python3 -m http.server 8000'
EOF

    # Source it from shells
    for rc in ~/.bashrc ~/.zshrc; do
        if [[ -f "$rc" ]] && ! grep -q "pentest-tools-aliases.sh" "$rc"; then
            echo "[ -f \$HOME/.config/pentest-tools-aliases.sh ] && source \$HOME/.config/pentest-tools-aliases.sh" >> "$rc"
        fi
    done
    if [[ -d "$HOME/.config/fish/conf.d" ]]; then
        cat > "$HOME/.config/fish/conf.d/pentest-tools.fish" <<EOF
# Convenience env vars for pentest tools
set -gx PENTEST_TOOLS "$tools_dir"
set -gx PEASS "$peass_dir"
set -gx PAYLOADS "$pat_dir"
set -gx STATIC_BINS "$static_dir"
set -gx LIGOLO "$ligolo_dir"
set -gx CHISEL "$chisel_dir"

# Quick access aliases
alias linpeas-here 'cp \$PEASS/linPEAS/linpeas.sh .'
alias winpeas-here 'cp \$PEASS/winPEAS/winPEASexe/winPEAS/bin/x64/Release/winPEASx64.exe .'
alias serve-tools 'cd \$PENTEST_TOOLS && python3 -m http.server 8000'
EOF
    fi

    ok "Manual tools downloaded to: $tools_dir"
    info "Quick access:"
    info "  \$PENTEST_TOOLS = $tools_dir"
    info "  \$PEASS         = $peass_dir       (linpeas/winpeas)"
    info "  \$PAYLOADS      = $pat_dir         (PayloadsAllTheThings)"
    info "  \$LIGOLO        = $ligolo_dir      (proxy + agent.exe)"
    info "  \$CHISEL        = $chisel_dir      (linux + windows)"
    info "  \$STATIC_BINS   = $static_dir      (static nmap, socat for upload)"
    info "  serve-tools    → starts python http.server in tools dir"
}

# =============================================================================
# 7c. Python pentest libraries (via pip --user)
# =============================================================================
install_python_pentest_libs() {
    section "7c. Python pentest libraries"
    if [[ $SKIP_PENTEST -eq 1 ]]; then
        warn "Skipped"
        return 0
    fi

    if ! confirm "Install Python pentest libraries (impacket helpers, ldap3, etc.)?"; then
        warn "Skipped"
        return 0
    fi

    local pip_pkgs=(
        # Network/protocol libraries
        ldap3                     # LDAP queries
        dnspython                 # DNS toolkit
        pyOpenSSL
        cryptography

        # AD-specific
        bloodhound                # Python BloodHound
        adidnsdump                # AD DNS dumping (also AUR)

        # Web testing
        requests
        urllib3
        beautifulsoup4
        mechanicalsoup
        playwright

        # Crypto / hash
        pycryptodome
        passlib

        # Misc utilities
        rich                      # pretty terminal output
        colorama
        pyfiglet
        tabulate
        prettytable

        # OSCP scripts often need these
        pwntools                  # exploit dev framework
        ropper                    # ROP gadgets
        ROPgadget                 # ROP gadgets (alt)
        capstone                  # disassembly engine
        unicorn                   # CPU emulator
        keystone-engine           # assembler
    )

    info "Packages: ${#pip_pkgs[@]} libraries"
    pip3 install --user --break-system-packages "${pip_pkgs[@]}" 2>&1 | tail -10 \
        || pip3 install --user "${pip_pkgs[@]}" 2>&1 | tail -10 \
        || warn "Some pip packages failed"

    ok "Python pentest libraries done"
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

    # On Arch, net-snmp provides snmpwalk/snmpget. On Kali they're in 'snmp' package.
    # No symlinks needed — same binaries, just different package name.
    if command -v snmpwalk >/dev/null 2>&1; then
        ok "snmpwalk/snmpget available (from net-snmp)"
    fi

    # exiftool is in perl-image-exiftool on Arch — already installs as 'exiftool'
    if command -v exiftool >/dev/null 2>&1; then
        ok "exiftool available"
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
# 8b. Desktop integration — default apps, right-click, flameshot keybinding
# =============================================================================
setup_desktop_integration() {
    section "8b. Desktop integration (defaults, right-click, flameshot)"
    if [[ $SKIP_MENU -eq 1 ]]; then
        warn "Skipped (--skip-menu)"
        return 0
    fi

    # === VS Code as default editor ===
    if command -v code >/dev/null 2>&1; then
        info "Setting VS Code as default editor for text/code files..."

        # Set as default for all text/code-ish MIME types
        local vscode_mimes=(
            text/plain
            text/markdown
            text/x-python
            text/x-shellscript
            text/x-csrc
            text/x-c++src
            text/x-java
            text/x-go
            text/x-rust
            text/x-ruby
            text/javascript
            application/javascript
            application/json
            application/xml
            text/xml
            text/html
            text/css
            text/yaml
            application/x-yaml
            text/x-makefile
            text/x-cmake
            text/csv
            text/x-log
        )

        for mime in "${vscode_mimes[@]}"; do
            xdg-mime default code.desktop "$mime" 2>/dev/null || true
        done

        # Set EDITOR env var for shells
        info "Setting \$EDITOR=code in shell rc files..."

        # Fish
        if [[ -d "$HOME/.config/fish/conf.d" ]]; then
            cat > "$HOME/.config/fish/conf.d/editor.fish" <<'EOF'
# Default editor: VS Code
set -gx EDITOR "code --wait"
set -gx VISUAL "code --wait"
set -gx SUDO_EDITOR "code --wait"
EOF
        fi

        # Bash
        if [[ -f "$HOME/.bashrc" ]] && ! grep -q "EDITOR=.*code" "$HOME/.bashrc"; then
            cat >> "$HOME/.bashrc" <<'EOF'

# Default editor: VS Code
export EDITOR="code --wait"
export VISUAL="code --wait"
export SUDO_EDITOR="code --wait"
EOF
        fi

        # Zsh
        if [[ -f "$HOME/.zshrc" ]] && ! grep -q "EDITOR=.*code" "$HOME/.zshrc"; then
            cat >> "$HOME/.zshrc" <<'EOF'

# Default editor: VS Code
export EDITOR="code --wait"
export VISUAL="code --wait"
export SUDO_EDITOR="code --wait"
EOF
        fi

        # git uses $EDITOR but be explicit
        git config --global core.editor "code --wait"

        ok "VS Code is now default editor"
    else
        warn "VS Code not found — skipping default editor setup"
    fi

    # === Ghostty as default terminal ===
    if command -v ghostty >/dev/null 2>&1; then
        info "Setting Ghostty as default terminal for KDE..."

        # KDE/Plasma default terminal config
        # Plasma 6 uses ~/.config/kdeglobals
        local kdeglobals="$HOME/.config/kdeglobals"
        if [[ -f "$kdeglobals" ]]; then
            # Remove old TerminalApplication if present
            sed -i '/^TerminalApplication=/d' "$kdeglobals"
            sed -i '/^TerminalService=/d' "$kdeglobals"
        fi

        # Add Ghostty as terminal
        if grep -q "^\[General\]" "$kdeglobals" 2>/dev/null; then
            # Insert after [General]
            sed -i '/^\[General\]$/a TerminalApplication=ghostty\nTerminalService=com.mitchellh.ghostty.desktop' "$kdeglobals"
        else
            cat >> "$kdeglobals" <<EOF

[General]
TerminalApplication=ghostty
TerminalService=com.mitchellh.ghostty.desktop
EOF
        fi

        # Default scheme handler — for "Open in Terminal" actions
        xdg-mime default com.mitchellh.ghostty.desktop x-scheme-handler/terminal 2>/dev/null || true

        # x-terminal-emulator for cli scripts that look for it (Debian-ism)
        sudo mkdir -p /usr/local/bin
        sudo ln -sf "$(command -v ghostty)" /usr/local/bin/x-terminal-emulator

        ok "Ghostty set as default terminal"
    else
        warn "Ghostty not found — skipping default terminal setup"
    fi

    # === "Open Terminal Here" right-click on desktop AND Dolphin ===
    if command -v ghostty >/dev/null 2>&1; then
        info "Adding 'Open Terminal Here' right-click action..."

        # Service menu directory (Plasma 6 path)
        local svc_menus_dir="$HOME/.local/share/kio/servicemenus"
        mkdir -p "$svc_menus_dir"

        # Service file works in Dolphin AND on the desktop (folderview)
        cat > "$svc_menus_dir/open-ghostty-here.desktop" <<'EOF'
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=inode/directory;
Actions=openGhosttyHere;
X-KDE-Priority=TopLevel
X-KDE-StartupNotify=false

[Desktop Action openGhosttyHere]
Name=Open Terminal Here
Icon=utilities-terminal
Exec=ghostty --working-directory=%f
EOF
        chmod +x "$svc_menus_dir/open-ghostty-here.desktop"

        # Plasma 5 fallback (older path, harmless if not used)
        local svc_menus_legacy="$HOME/.local/share/kservices5/ServiceMenus"
        mkdir -p "$svc_menus_legacy"
        cp "$svc_menus_dir/open-ghostty-here.desktop" "$svc_menus_legacy/" 2>/dev/null || true

        ok "'Open Terminal Here' added (right-click on desktop or in Dolphin)"
    fi

    # === Flameshot global keybinding (PrintScreen) ===
    if command -v flameshot >/dev/null 2>&1; then
        info "Configuring Flameshot global keybindings..."

        # KDE custom shortcuts file
        local khotkeysrc="$HOME/.config/kglobalshortcutsrc"

        # Remove existing flameshot bindings to avoid duplicates
        if [[ -f "$khotkeysrc" ]]; then
            # Backup first
            cp "$khotkeysrc" "${khotkeysrc}.bak.$(date +%s)"
        fi

        # Add Flameshot config block (Plasma uses .desktop-based shortcuts)
        # Method: create a .desktop file in autostart that registers shortcut
        mkdir -p "$HOME/.config/autostart"

        # Make sure flameshot starts at login (so the tray icon is available)
        if [[ ! -f "$HOME/.config/autostart/flameshot.desktop" ]]; then
            cp /usr/share/applications/org.flameshot.Flameshot.desktop \
               "$HOME/.config/autostart/" 2>/dev/null || \
            cat > "$HOME/.config/autostart/flameshot.desktop" <<'EOF'
[Desktop Entry]
Name=Flameshot
GenericName=Screenshot tool
Comment=Powerful and easy to use screenshot tool
Icon=org.flameshot.Flameshot
Type=Application
Exec=flameshot
StartupNotify=false
Terminal=false
Categories=Graphics;Utility;
X-GNOME-Autostart-Phase=Applications
X-GNOME-Autostart-Delay=2
EOF
        fi

        # Configure flameshot for multi-monitor (default behavior in v12+)
        local fs_config="$HOME/.config/flameshot/flameshot.ini"
        mkdir -p "$(dirname "$fs_config")"
        if [[ ! -f "$fs_config" ]]; then
            cat > "$fs_config" <<'EOF'
[General]
checkForUpdates=false
contrastOpacity=188
contrastUiColor=#4476ff
disabledTrayIcon=false
saveAfterCopy=true
savePath=
savePathFixed=false
showHelp=true
showStartupLaunchMessage=false
startupLaunch=true
uiColor=#4476ff
useJpgForClipboard=false
EOF
            ok "Flameshot configured (multi-monitor enabled by default in v12+)"
        fi

        # Tell user how to bind PrintScreen
        info ""
        info "${C_YELLOW}MANUAL STEP for PrintScreen keybinding:${C_RESET}"
        info "  1. Open: System Settings → Shortcuts → Custom Shortcuts"
        info "  2. Edit > New > Global Shortcut > Command/URL"
        info "  3. Name:     'Flameshot screenshot'"
        info "     Trigger:  Print key"
        info "     Action:   flameshot gui"
        info "  Or run: ${C_BOLD}flameshot gui${C_RESET} from command line"
        info ""
        info "${C_YELLOW}Alternative — disable KDE's built-in Spectacle on PrintScreen:${C_RESET}"
        info "  System Settings → Shortcuts → Spectacle"
        info "  Clear all 'Print' bindings, then add to Flameshot above"
    fi

    ok "Desktop integration done"
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
        [Pentest-Tunnel]="Tunneling/Pivot|network-vpn"
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
      <Name>Tunneling/Pivot</Name>
      <Directory>Pentest-Tunnel.directory</Directory>
      <Include>
        <Or>
          <Filename>ligolo-ng.desktop</Filename>
          <Filename>ligolo.desktop</Filename>
          <Filename>chisel.desktop</Filename>
          <Filename>sshuttle.desktop</Filename>
          <Filename>gost.desktop</Filename>
          <Filename>proxychains4.desktop</Filename>
          <Filename>proxychains.desktop</Filename>
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
        [rustscan]="RustScan|edit-find|rustscan"
        [masscan]="masscan|edit-find|sudo masscan -h; read"
        [sqlmap]="sqlmap|edit-find|sqlmap"
        [gobuster]="Gobuster|edit-find|gobuster"
        [feroxbuster]="Feroxbuster|edit-find|feroxbuster"
        [ffuf]="ffuf|edit-find|ffuf"
        [nuclei]="Nuclei|edit-find|nuclei"
        [amass]="Amass|edit-find|amass"
        [subfinder]="Subfinder|edit-find|subfinder"
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
        [certipy]="Certipy (AD CS)|preferences-system-network|certipy -h; read"
        [autorecon]="AutoRecon|system-search|autorecon"
        [linpeas]="linPEAS|system-run|linpeas"
        [winpeas]="winPEAS|system-run|winpeas"
        [proxychains4]="ProxyChains|preferences-system-network|proxychains4 -h; read"
        [evil-winrm]="Evil-WinRM|preferences-system-network|evil-winrm"
        [sliver]="Sliver C2|applications-debugging|sliver"
        [sliver-server]="Sliver Server|applications-debugging|sudo sliver-server"
        [pwncat-cs]="pwncat-cs|applications-debugging|pwncat-cs"
        [ligolo-proxy]="Ligolo-ng Proxy|network-vpn|sudo ligolo-proxy -h; read"
        [chisel]="Chisel|network-vpn|chisel --help; read"
        [sshuttle]="sshuttle|network-vpn|sshuttle --help; read"
        [enum4linux]="enum4linux|preferences-system-network|enum4linux"
        [smbmap]="smbmap|preferences-system-network|smbmap -h; read"
        [hashid]="hash-identifier|dialog-password|hashid"
        [cewl]="CeWL|edit-find|cewl --help; read"
        [pspy]="pspy|system-run|pspy"
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
  ${C_GREEN}✓${C_RESET} Kali basics:   netcat, rlwrap, gobuster, ffuf, hashcat,
                  nmap, masscan, sqlmap, nuclei, smbmap, enum4linux,
                  metasploit, exploitdb, wireshark, aircrack-ng, etc.
EOF

    [[ $SKIP_BLACKARCH -eq 0 && $SKIP_PENTEST -eq 0 ]] && cat <<EOF
  ${C_GREEN}✓${C_RESET} BlackArch:     repo + officials metapackage (~150 tools)
  ${C_GREEN}✓${C_RESET} Wordlists:     seclists, wordlists, fuzzdb (rockyou auto-decompressed)
EOF

    [[ $SKIP_AUR -eq 0 && $SKIP_PENTEST -eq 0 ]] && cat <<EOF
  ${C_GREEN}✓${C_RESET} AUR pentest:   ${C_BOLD}Active Directory:${C_RESET}  kerbrute, certipy, netexec(nxc),
                                      evil-winrm, BloodHound (py+rust),
                                      adidnsdump, powerview, pywerview
                  ${C_BOLD}Tunneling/Pivot:${C_RESET}   ${C_YELLOW}ligolo-ng${C_RESET}, chisel, sshuttle, gost
                  ${C_BOLD}Web Testing:${C_RESET}      Burp, ZAP, caido, amass, subfinder,
                                      httpx, katana, dalfox
                  ${C_BOLD}Exploitation/C2:${C_RESET}  sliver, pwncat-cs, msfpc
                  ${C_BOLD}Recon:${C_RESET}            autorecon, rustscan, gowitness, eyewitness
                  ${C_BOLD}Privesc:${C_RESET}          peass-ng (lin/winpeas), pspy, exploit-suggester
                  ${C_BOLD}Cracking:${C_RESET}         crackmapexec, hashid, hcxtools
                  ${C_BOLD}Reverse Eng:${C_RESET}      ghidra, cutter, pwndbg, gef, peda
                  ${C_BOLD}Misc:${C_RESET}             PayloadsAllTheThings, sherlock, gitleaks
EOF

    [[ $SKIP_PENTEST -eq 0 ]] && cat <<EOF
  ${C_GREEN}✓${C_RESET} Manual tools:  ~/.local/share/pentest-tools/
                  ├── PEASS-ng/         (linpeas + winpeas)
                  ├── PowerSploit/
                  ├── PayloadsAllTheThings/
                  ├── hacktricks/       (offline reference)
                  ├── mimikatz/
                  ├── ligolo-ng/        (proxy_linux + agent.exe)
                  ├── chisel/           (linux + windows binaries)
                  └── static-bins/      (static nmap, socat for upload)
  ${C_GREEN}✓${C_RESET} Python libs:   pwntools, ldap3, dnspython, ROPgadget,
                  capstone, unicorn, keystone, bloodhound
EOF

    [[ $SKIP_MENU -eq 0 && $SKIP_PENTEST -eq 0 ]] && cat <<EOF
  ${C_GREEN}✓${C_RESET} KDE Menu:      Pentest Tools/ folder with 12 subcategories
  ${C_GREEN}✓${C_RESET} Default editor: VS Code (text/code/json/etc files)
  ${C_GREEN}✓${C_RESET} Default term:  Ghostty (Konsole replaced)
  ${C_GREEN}✓${C_RESET} Right-click:   "Open Terminal Here" on desktop & Dolphin
  ${C_GREEN}✓${C_RESET} Flameshot:     installed + autostart enabled (multi-monitor)
  ${C_GREEN}✓${C_RESET} Wordlists:     Kali-compatible paths under /usr/share/wordlists/
                  ├── seclists  → /usr/share/seclists
                  ├── dirb      → /usr/share/dirb/wordlists
                  ├── dirbuster → seclists/Discovery/Web-Content
                  ├── fuzzdb    → /usr/share/fuzzdb
                  └── rockyou.txt
EOF

    cat <<EOF

  ${C_YELLOW}Next steps:${C_RESET}
    1. ${C_BOLD}Logout / login${C_RESET} for wireshark group + KDE menu refresh + env vars
    2. Test:  ${C_BOLD}nmap -sV scanme.nmap.org${C_RESET}     (no sudo needed!)
    3. Test:  Right-click on desktop → "Open Terminal Here"   (should open Ghostty)
    4. Test:  ${C_BOLD}ls /usr/share/wordlists/${C_RESET}     (should show seclists, dirb, dirbuster, ...)
    5. ${C_YELLOW}Bind Flameshot to PrintScreen:${C_RESET}
       System Settings → Shortcuts → Spectacle → clear all 'Print' bindings
       System Settings → Shortcuts → Custom → New → Global Shortcut → Command
       Name: "Flameshot"  |  Trigger: Print  |  Action: ${C_BOLD}flameshot gui${C_RESET}
    6. Open KDE Application Menu — find ${C_BOLD}'Pentest Tools'${C_RESET}
    7. Useful env vars (set in fish/bash/zsh):
       ${C_BOLD}\$PEASS${C_RESET}        → linpeas/winpeas folder
       ${C_BOLD}\$PAYLOADS${C_RESET}     → PayloadsAllTheThings folder
       ${C_BOLD}\$LIGOLO${C_RESET}       → ligolo-ng binaries
       ${C_BOLD}\$CHISEL${C_RESET}       → chisel binaries
       ${C_BOLD}\$STATIC_BINS${C_RESET}  → static binaries for upload
       ${C_BOLD}\$EDITOR${C_RESET}       → "code --wait"
    8. Quick aliases:
       ${C_BOLD}linpeas-here${C_RESET}    copies linpeas.sh to current dir
       ${C_BOLD}winpeas-here${C_RESET}    copies winPEASx64.exe to current dir
       ${C_BOLD}serve-tools${C_RESET}     starts python http.server in tools dir

  ${C_BLUE}Log file:${C_RESET} $LOG_FILE

  ${C_GREEN}OSCP-ready setup complete. Time to break things responsibly.${C_RESET}

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
    install_manual_tools
    install_python_pentest_libs
    fix_kali_compatibility
    setup_desktop_integration
    setup_kde_menu
    final_summary
}

main "$@"
