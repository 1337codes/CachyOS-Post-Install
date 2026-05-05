# CachyOS Post-Install — OSCP Edition v2.1

Sets up a fresh CachyOS install for daily use + complete OSCP-ready pentest workflow with one command. Includes desktop integration: VS Code as default editor, Ghostty as default terminal, "Open Terminal Here" right-click, Flameshot for multi-monitor screenshots, and Kali-compatible wordlist paths.

## Quick start

```bash
chmod +x cachyos-postinstall.sh
./cachyos-postinstall.sh                # interactive
./cachyos-postinstall.sh --yes          # accept all defaults
```

Run as **your normal user**, not as root. The script will `sudo` individual commands as needed.

## What it installs

### Daily apps
- Google Chrome (AUR)
- Joplin Desktop (AUR)
- Visual Studio Code (MS marketplace build, AUR) — **set as default editor**
- Ghostty terminal — **set as default terminal**
- Flameshot — multi-monitor screenshot tool
- KeePassXC — password manager (for engagement creds)
- GIMP — image editing for screenshots
- Kdenlive — video editing for PoCs

### Desktop integration

**VS Code as default editor for:**
- Plain text, markdown, JSON, XML, YAML
- All source code (Python, JS, Go, Rust, C/C++, Java, Ruby, Shell)
- HTML, CSS, log files, CSV
- `$EDITOR`, `$VISUAL`, `$SUDO_EDITOR` set to `code --wait`
- `git` uses VS Code via `core.editor` config

**Ghostty as default terminal:**
- KDE `TerminalApplication` set to ghostty
- `/usr/local/bin/x-terminal-emulator` symlinked to ghostty
- `xdg-mime` handler for `x-scheme-handler/terminal`

**"Open Terminal Here" right-click:**
- Works on the **Desktop** (right-click empty area)
- Works in **Dolphin** (right-click in any folder)
- Service file at `~/.local/share/kio/servicemenus/`

**Flameshot:**
- Auto-starts on login (tray icon visible)
- Multi-monitor support enabled by default (v12+)
- Save-after-copy enabled
- *Manual step*: bind to PrintScreen via System Settings (instructions printed at end)

### Kali-compatible wordlist paths

After install, these all work just like on Kali:

```
/usr/share/wordlists/seclists       → /usr/share/seclists
/usr/share/wordlists/SecLists       → /usr/share/seclists  (case variant)
/usr/share/wordlists/dirb           → /usr/share/dirb/wordlists
/usr/share/wordlists/dirbuster      → seclists/Discovery/Web-Content (fallback)
/usr/share/wordlists/fuzzdb         → /usr/share/fuzzdb
/usr/share/wordlists/rockyou.txt    → seclists rockyou.txt
```

So Kali OSCP tutorials with paths like:
- `gobuster dir -w /usr/share/wordlists/dirb/common.txt`
- `wfuzz -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt`
- `hashcat -a 0 -m 1000 hashes.txt /usr/share/wordlists/rockyou.txt`

**just work** without modification.

### Dev tools
- Languages: Python 2 + 3, Node.js, Go, Rust, Ruby
- Shells: fish, zsh, tmux
- VCS: git, base-devel
- Editors: neovim, vim, nano

### Modern CLI replacements
- eza, bat, fd, ripgrep, fzf, btop, jq, yq, fastfetch

### Kali-default basics
- netcat (gnu + openbsd + ncat), socat, rlwrap, expect
- **Web fuzzing:** gobuster, feroxbuster, ffuf, wfuzz, dirsearch, gospider, **dirb**
- **Web analysis:** nikto, whatweb, wafw00f, sslscan
- **Web exploitation:** sqlmap, nuclei, commix, xsser
- **Cracking:** hashcat, john, hydra, medusa, ncrack, cewl
- **AD/Windows:** smbclient, smbmap, enum4linux, impacket, responder, bloodhound
- **Exploitation:** metasploit, exploitdb (searchsploit)
- **Sniffers:** wireshark, tcpdump, bettercap, ettercap
- **Wireless:** aircrack-ng, reaver, wifite
- **Forensics:** binwalk, foremost, steghide, exiftool
- **Tunneling:** proxychains-ng, tor
- **Network:** masscan, nmap, dnsutils, mtr, traceroute
- **SNMP:** snmp tools, onesixtyone, snmpcheck
- **Daily extras:** flameshot, keepassxc, gimp, kdenlive

### BlackArch
- BlackArch repository (with SHA1-verified strap.sh)
- `blackarch-officials` metapackage (~150 curated tools)
- Wordlists: seclists, wordlists, fuzzdb, **dirb** (rockyou auto-decompressed)

### AUR pentest tools — OSCP edition (~3-5 GB)

**Active Directory & Windows:**
kerbrute-bin, certipy-ad, netexec-git (nxc), evil-winrm, bloodhound-python-git,
rusthound, adidnsdump-git, powerview-git, pywerview, ldapdomaindump, donpapi-git

**Tunneling & Pivoting:**
⭐ ligolo-ng, chisel, sshuttle, gost, sshpass

**Web App Testing:**
burpsuite, zaproxy, caido-bin, amass, subfinder, httpx-bin, katana-bin,
dalfox, knock, photon-git

**Exploitation & C2:**
sliver-bin, pwncat-cs, revshells, msfpc

**Recon & Enumeration:**
autorecon, rustscan, nuclei-templates, gowitness, eyewitness, dnsx-bin, nmap-vulners

**Privesc Helpers:**
peass-ng (linpeas + winpeas), linux-exploit-suggester, windows-exploit-suggester, pspy-bin

**Cracking & Hashing:**
crackmapexec, hashid, name-that-hash, hash-identifier, ophcrack, hcxtools, hcxdumptool

**Reverse Engineering:**
ghidra, cutter, pwndbg, gef, peda, binaryninja-free

**Misc:**
payloadsallthethings-git, sherlock, holehe, gitleaks, trufflehog-bin

### Manual tool downloads (~/.local/share/pentest-tools/)

- **PEASS-ng** (linpeas + winpeas)
- **PowerSploit** (PowerShell post-exploit)
- **PayloadsAllTheThings** (~500MB)
- **HackTricks** (offline reference)
- **Mimikatz** (latest binary auto-fetched)
- **Ligolo-ng** binaries (proxy_linux + agent.exe)
- **Chisel** binaries (linux + windows)
- **Static binaries** (`nmap`, `socat`) for upload to targets

### Python pentest libraries

pwntools, ROPgadget, capstone, unicorn, keystone, ldap3, dnspython,
bloodhound, requests, beautifulsoup4, mechanicalsoup, pycryptodome, passlib,
rich, colorama, pyfiglet, tabulate

### Compatibility fixes
- `impacket-*` symlinks
- `crackmapexec` ↔ `nxc` symlinks
- `enum4linux` ↔ `enum4linux-ng` symlink
- `nmap` raw-socket capability (SYN scan without sudo)
- Wireshark group membership

### KDE Application Menu

**Pentest Tools** folder with **12 subcategories**:
Recon, Scanner, Web Apps, Crackers, Wireless, Exploitation, Post-Exploitation,
Active Directory, Tunneling/Pivot ⭐, Forensics, Reverse Engineering, Sniffers

Auto-generates `.desktop` files for ~40 CLI tools. Tools open in Ghostty when launched from menu.

### Convenience env vars (auto-set in fish/bash/zsh)

```bash
$PENTEST_TOOLS  → ~/.local/share/pentest-tools/
$PEASS          → linpeas/winpeas folder
$PAYLOADS       → PayloadsAllTheThings folder
$LIGOLO         → ligolo-ng binaries
$CHISEL         → chisel binaries
$STATIC_BINS    → static binaries for upload
$EDITOR         → "code --wait"
$VISUAL         → "code --wait"
$SUDO_EDITOR    → "code --wait"
```

Aliases:
- `linpeas-here` — copies linpeas.sh to current dir
- `winpeas-here` — copies winPEASx64.exe to current dir
- `serve-tools` — starts `python3 -m http.server 8000` in tools dir

## Flags

| Flag | Purpose |
|---|---|
| `-y`, `--yes` | Non-interactive mode |
| `--skip-pentest` | Skip ALL pentest tools (only daily apps + dev) |
| `--skip-blackarch` | Skip BlackArch repo |
| `--skip-aur` | Skip all AUR packages |
| `--skip-menu` | Skip KDE menu + desktop integration |
| `-h`, `--help` | Show help |

## Requirements

- CachyOS Linux (or vanilla Arch)
- Run as your normal user
- Internet connection
- ~10 GB free disk space

## After running

1. **Logout/login** (for wireshark group + KDE menu refresh + env vars + default term)
2. Test: `nmap -sV scanme.nmap.org` (works without sudo!)
3. Test: Right-click on desktop → "Open Terminal Here" (should open Ghostty)
4. Test: `ls /usr/share/wordlists/` (should show seclists, dirb, dirbuster, ...)
5. **Bind Flameshot to PrintScreen** (manual step):
   - System Settings → Shortcuts → Spectacle → clear all 'Print' bindings
   - System Settings → Shortcuts → Custom → New → Global Shortcut → Command
   - Name: "Flameshot" | Trigger: Print | Action: `flameshot gui`
6. Open KDE Application Menu → find **Pentest Tools** folder

## Logs

`~/.cache/cachyos-postinstall/postinstall-<timestamp>.log`

## Idempotent

Safe to re-run. Already-installed packages skipped. AUR packages won't re-build if up to date.
Manual downloads (git repos) get `git pull` if already cloned. Symlinks check for existence first.

## Tool counts per source

| Source | Tools | Size |
|---|---|---|
| pacman base-dev | ~50 | ~500 MB |
| pacman Kali-basics | ~75 | ~1 GB |
| BlackArch officials | ~150 | ~3 GB |
| AUR pentest | ~70 | ~3 GB |
| Manual git clones | 4 repos | ~600 MB |
| Static binaries | 2 | ~10 MB |
| Python libs | ~25 | ~100 MB |
| **Total** | **~375 tools** | **~8 GB** |

## License

MIT
