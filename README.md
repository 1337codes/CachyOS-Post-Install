# CachyOS Post-Install

Sets up a fresh CachyOS install for daily use + pentest workflow with one command.

## Quick start

```bash
chmod +x cachyos-postinstall.sh
./cachyos-postinstall.sh                # interactive
./cachyos-postinstall.sh --yes          # accept all defaults
```

Run as **your normal user**, not as root. The script will `sudo` individual commands as needed.

## What it installs

**Daily apps**
- Google Chrome (AUR)
- Joplin Desktop (AUR)
- Visual Studio Code (MS marketplace build, AUR)
- Ghostty terminal

**Dev tools**
- Languages: Python 2 + 3, Node.js, Go, Rust, Ruby
- Shells: fish, zsh, tmux
- VCS: git, base-devel
- Editors: neovim, vim, nano

**Modern CLI replacements**
- eza, bat, fd, ripgrep, fzf, btop, jq, yq, fastfetch

**Kali-default basics** (the tools every OSCP/HTB tutorial assumes)
- netcat (gnu + openbsd + ncat), socat, rlwrap
- gobuster, feroxbuster, ffuf, wfuzz, dirsearch
- nikto, whatweb, wafw00f, sqlmap, nuclei
- hashcat, john, hydra, medusa, ncrack
- smbclient, impacket, responder, bloodhound
- metasploit, exploitdb (searchsploit)
- wireshark, tcpdump, bettercap
- aircrack-ng, reaver
- binwalk, foremost, steghide, exiftool
- proxychains-ng, tor

**BlackArch**
- BlackArch repository (with SHA1-verified strap.sh)
- `blackarch-officials` metapackage (~150 curated tools)
- Wordlists: seclists, wordlists, fuzzdb (rockyou auto-decompressed)

**AUR pentest tools**
- kerbrute-bin, autorecon, certipy-ad, sliver-bin, netexec-git, pwndbg, ghidra, burpsuite

**Compatibility fixes**
- `impacket-*` symlinks (so Kali tutorials work on Arch)
- `crackmapexec` ↔ `nxc` symlinks
- `enum4linux` ↔ `enum4linux-ng` symlink
- `nmap` raw-socket capability (SYN scan without sudo)
- Wireshark group membership for live capture

**KDE Application Menu**
- New top-level **Pentest Tools** folder with subcategories:
  - Recon
  - Scanner
  - Web Apps
  - Crackers
  - Wireless
  - Exploitation
  - Post-Exploitation
  - Active Directory
  - Forensics
  - Reverse Engineering
  - Sniffers
- Auto-generates `.desktop` files for CLI tools so they show in the menu
- Tools open in Ghostty when launched from menu

## Flags

| Flag | Purpose |
|---|---|
| `-y`, `--yes` | Non-interactive mode |
| `--skip-pentest` | Skip pentest tools (only daily apps + dev) |
| `--skip-blackarch` | Skip BlackArch repo |
| `--skip-aur` | Skip all AUR packages |
| `--skip-menu` | Skip KDE menu reorganization |
| `-h`, `--help` | Show help |

## Requirements

- CachyOS Linux (or vanilla Arch)
- Run as your normal user
- Internet connection
- ~5 GB free disk space

## Logs

`~/.cache/cachyos-postinstall/postinstall-<timestamp>.log`

Useful when an install fails halfway and you want to see what happened.

## After running

1. **Logout/login** (for wireshark group + KDE menu refresh)
2. Test: `nmap -sV scanme.nmap.org` (works without sudo!)
3. Open KDE Application Menu — find **Pentest Tools** folder

## Idempotent

Safe to re-run. Already-installed packages skipped. AUR packages won't re-build if up to date.

## Customizing

Add packages by editing the relevant function in the script:

- `install_base_dev()` — dev tools
- `install_kali_basics()` — pentest essentials
- `install_aur_pentest()` — AUR pentest tools
- `setup_kde_menu()` → `cli_tools` array — CLI tools that need .desktop files

The KDE menu structure lives in `setup_kde_menu()`. Add new categories by:
1. Adding to the `categories` associative array
2. Adding a `<Menu>` block to the heredoc
3. Adding `.desktop` filenames to the `<Include>` block

## License

MIT
