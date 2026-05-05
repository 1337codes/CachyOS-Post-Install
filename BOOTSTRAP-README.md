# CachyOS Bootstrap — Fresh Install to Pentest Workstation

Complete recovery guide for CachyOS on an ASUS ROG Flow Z13 (GZ302EA).
From a fresh CachyOS install to a fully configured pentest system,
**100% via terminal** — no browser, no GUI required.

---

## TL;DR — Set username once, then copy-paste

```bash
# === Set your GitHub username ONCE ===
export GH_USER="your-github-username"

# === Then copy-paste everything below ===

# 1. Update system
sudo pacman -Syyu --noconfirm

# 2. Bootstrap yay (AUR helper)
sudo pacman -S --needed --noconfirm git base-devel
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin && makepkg -si --noconfirm && cd ~ && rm -rf /tmp/yay-bin

# 3. Clone all setup repos
mkdir -p ~/Projects && cd ~/Projects
git clone "https://github.com/${GH_USER}/z13-setup.git"
git clone "https://github.com/${GH_USER}/cachyos-postinstall.git"
git clone "https://github.com/1337codes/Arch-tools.git"

# 4. Run the scripts
cd ~/Projects/z13-setup           && chmod +x *.sh && ./z13-cachyos-setup.sh
cd ~/Projects/cachyos-postinstall && chmod +x *.sh && ./cachyos-postinstall.sh --yes
cd ~/Projects/Arch-tools          && chmod +x *.sh && ./tools-setup.sh install -y

# 5. Reboot
sudo reboot
```

Done in ~45 minutes.

> 💡 **The `export GH_USER=...` only persists for your current shell session.**
> If you reboot or open a new terminal mid-install, set it again.

---

## What goes where on GitHub

To make "everything via terminal" possible, you need the three scripts **on GitHub**.
Public repos work fine (no credentials needed). Private repos work too with SSH key.

### Recommended repo structure

```
github.com/<yourname>/
├── z13-setup/                          (hardware fixes)
│   └── z13-cachyos-setup.sh
│
├── cachyos-postinstall/                (apps + pentest tools + KDE menu)
│   ├── cachyos-postinstall.sh
│   └── README.md
│
└── Arch-tools/                         (already exists: 1337codes/Arch-tools)
    ├── tools-setup.sh
    ├── tools.json
    ├── README.md
    └── patches/
        └── http-smb-server-tools.py
```

### First-time push from your Z13

From your current working install, before you reinstall:

```bash
# Set username
export GH_USER="your-github-username"

# Move scripts into project folders
mkdir -p ~/Projects/z13-setup ~/Projects/cachyos-postinstall
mv ~/Downloads/z13-cachyos-setup.sh ~/Projects/z13-setup/
mv ~/Downloads/cachyos-postinstall.sh ~/Projects/cachyos-postinstall/
mv ~/Downloads/BOOTSTRAP-README.md ~/Projects/cachyos-postinstall/README.md

# Push z13-setup
cd ~/Projects/z13-setup
git init
echo "# Z13 CachyOS Setup" > README.md
git add .
git commit -m "Initial Z13 setup script"
git branch -M main
git remote add origin "git@github.com:${GH_USER}/z13-setup.git"
git push -u origin main

# Push cachyos-postinstall
cd ~/Projects/cachyos-postinstall
git init
git add .
git commit -m "Initial post-install script"
git branch -M main
git remote add origin "git@github.com:${GH_USER}/cachyos-postinstall.git"
git push -u origin main
```

**After this, you can recover your entire setup with the TL;DR snippet.**

---

## Make GH_USER permanent (optional)

If you want `$GH_USER` available in every shell forever, add it to your shell rc:

### Fish

```bash
echo "set -gx GH_USER your-github-username" >> ~/.config/fish/config.fish
```

### Bash

```bash
echo "export GH_USER=your-github-username" >> ~/.bashrc
```

### Zsh

```bash
echo "export GH_USER=your-github-username" >> ~/.zshrc
```

Then on any future terminal, `$GH_USER` is set automatically — no need to `export` it again.

---

## Step-by-step (with explanation per step)

### Step 0 — Fresh CachyOS install

You just finished installing via Calamares. You're logged in as `alien` in fish shell.
No Chrome, no yay, no apps.

```bash
# Verify who you are
whoami       # → alien
echo $SHELL  # → /usr/bin/fish

# Set your GitHub username for this session
export GH_USER="your-github-username"
echo $GH_USER  # verify it's set
```

### Step 1 — System update

```bash
sudo pacman -Syyu
```

Why: ISO is always older than repos. This pulls in security fixes and ensures all
following installs work with up-to-date dependencies.

**Time:** 3-10 min depending on internet.

### Step 2 — Bootstrap yay

CachyOS ships `pacman` by default but **not yay** (AUR helper). For Chrome, VS Code,
Joplin etc. you need AUR.

```bash
# Install build dependencies
sudo pacman -S --needed git base-devel

# Clone yay-bin (precompiled, faster than source)
cd /tmp
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si

# Cleanup
cd ~
rm -rf /tmp/yay-bin

# Verify
yay --version
```

**Important:** correct URL is `aur.archlinux.org/yay-bin.git` — NOT
`aur.archlinux.org/packages/yay-bin.git`.

**Time:** 1-2 min.

### Step 3 — Clone your setup repos

```bash
mkdir -p ~/Projects && cd ~/Projects

# Hardware fixes
git clone "https://github.com/${GH_USER}/z13-setup.git"

# Daily apps + pentest + KDE menu
git clone "https://github.com/${GH_USER}/cachyos-postinstall.git"

# Tools-installer (1337codes — public, no GH_USER needed)
git clone https://github.com/1337codes/Arch-tools.git
```

**Time:** 30 sec.

### Step 4 — Z13 hardware setup

This must run **first**. Fixes OLED issues, suspend bugs, Bluetooth, MT7925 WiFi etc.

```bash
cd ~/Projects/z13-setup
chmod +x z13-cachyos-setup.sh
./z13-cachyos-setup.sh
```

Follow prompts. **Reboot required afterwards** for kernel parameters.

**Time:** 15-30 min (compiles things + downloads).

### Step 5 — Reboot after hardware setup

```bash
sudo reboot
```

Test after boot:
- WiFi works
- Bluetooth works
- Suspend works (close lid for a moment)
- OLED contrast looks right

> ⚠️ **After reboot, your `$GH_USER` variable is gone** (unless you made it permanent
> in your shell rc — see "Make GH_USER permanent" section above). Re-export it:
> `export GH_USER="your-github-username"`

### Step 6 — Daily apps + pentest tools

Now the big installer with Chrome, Joplin, VS Code, Ghostty, BlackArch, KDE menu folders.

```bash
cd ~/Projects/cachyos-postinstall
chmod +x cachyos-postinstall.sh

# Interactive (confirm each section)
./cachyos-postinstall.sh

# Or install everything in one go
./cachyos-postinstall.sh --yes
```

**Time:** 30-45 min (BlackArch officials = ~3GB).

### Step 7 — Logout/login

For wireshark group activation + KDE menu refresh:

```bash
loginctl terminate-user alien
# Or: KDE → Logout → log in again
```

### Step 8 — Personal pentest tools (1337codes)

For http-smb-server, ncscanner, cve-suggester, NXC-PREY, ligolo etc:

```bash
mkdir -p ~/Desktop/tools && cd ~/Desktop/tools
git clone https://github.com/1337codes/Arch-tools.git
cd Arch-tools

# Run installer
./tools-setup.sh install -y

# Activate aliases
exec fish
```

Test:
```bash
type tools           # → function definition
cve --help           # → should work
sudo tools --help    # → patched cross-distro tools.py
```

**Time:** 5-10 min.

### Step 9 — Restore your data

#### Joplin

```bash
joplin-desktop &
# File → Import → JEX
# Point to your JEX backup
```

#### SSH keys

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Copy keys from USB/cloud:
cp /run/media/alien/<USB>/ssh-backup/id_* ~/.ssh/
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/id_*.pub
```

#### Git config

```bash
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
git config --global init.defaultBranch main

# SSH agent for SSH keys
ssh-add ~/.ssh/id_ed25519
```

#### OpenVPN configs

```bash
mkdir -p ~/Documents/vpn-configs
cp /run/media/alien/<USB>/*.ovpn ~/Documents/vpn-configs/
```

#### BurpSuite Pro

Copy .sh installer and license file from USB:

```bash
cp /run/media/alien/<USB>/burpsuite_pro_linux_v2026_*.sh ~/Downloads/
chmod +x ~/Downloads/burpsuite_pro_linux_v*.sh
sudo bash ~/Downloads/burpsuite_pro_linux_v*.sh
# At prompts: Enter, Enter, /opt/BurpSuitePro/, Enter
# Activate with your license key after launch
```

---

## Optional post-setup

### Snapper baseline snapshot

```bash
sudo snapper -c root create --description "Fresh post-install + tools"
```

### Verify Limine kernel parameters (Z13-specific)

```bash
sudo cat /etc/default/limine
# Verify this is in there:
#   amd_pstate=guided rtc_cmos.use_acpi_alarm=1 amdgpu.dcdebugmask=0x600
```

If missing → `z13-cachyos-setup.sh` did something wrong, run again.

### Default browser in KDE

```bash
xdg-settings set default-web-browser google-chrome.desktop
```

### Fish shell as default

```bash
chsh -s /usr/bin/fish
# Logout/login — fish is now default
```

### Time setting (dual boot fix)

CachyOS uses UTC by default, Windows uses local time — this can give wrong time
in Windows. Fix:

```bash
sudo timedatectl set-local-rtc 1 --adjust-system-clock
```

---

## Troubleshooting

### `fish: Unknown command: yay`

Yay isn't installed yet. Run step 2 above.

### `target not found: base-level`

Typo. It's `base-devel`, not `base-level`.

```bash
sudo pacman -S --needed git base-devel
```

### `fatal: repository 'https://aur.archlinux.org/packages/yay-bin' not found`

Wrong URL. **Correct URL:**

```bash
git clone https://aur.archlinux.org/yay-bin.git
```

(No `/packages/` between them.)

### `makepkg: command not found`

Missing `base-devel`. Install:

```bash
sudo pacman -S --needed base-devel
```

### `git clone https://github.com//z13-setup.git` (empty username)

`$GH_USER` is not set or empty. Verify:

```bash
echo "[$GH_USER]"   # should show [your-github-username], not []
```

If empty, set it:

```bash
export GH_USER="your-github-username"
```

### Calamares "Hook 'openswap' cannot be found"

During install: don't use encrypted swap. Make swap partition without encryption,
and use separate LUKS for root.

Or skip swap partition entirely and create swapfile inside encrypted root afterwards:

```bash
sudo btrfs subvolume create /swap
sudo chattr +C /swap
sudo fallocate -l 32G /swap/swapfile
sudo chmod 600 /swap/swapfile
sudo mkswap /swap/swapfile
sudo swapon /swap/swapfile
echo '/swap/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab
```

### `pacman: error: failed to commit transaction (conflicting files)`

Two packages want the same file. Force overwrite:

```bash
sudo pacman -S --overwrite "*" <packagename>
```

### KDE menu folders show but are empty

Refresh menu cache:

```bash
kbuildsycoca6 --noincremental
update-desktop-database ~/.local/share/applications
```

Logout/login.

### Wireshark "permission denied" during capture

You're not in the `wireshark` group yet:

```bash
groups | grep wireshark    # should show wireshark
# If not:
sudo usermod -aG wireshark $USER
# Logout/login
```

### `nmap` asks for sudo

Setcap not granted (cachyos-postinstall.sh is supposed to do this):

```bash
sudo setcap cap_net_raw,cap_net_admin,cap_net_bind_service+eip $(command -v nmap)
```

---

## Total time estimate

| Phase | Time |
|---|---|
| 0. CachyOS install (Calamares) | 15 min |
| 1. System update | 5-10 min |
| 2. yay bootstrap | 2 min |
| 3. Clone repos | 1 min |
| 4. Z13 hardware setup | 15-30 min |
| 5. Reboot | 1 min |
| 6. Daily apps + pentest | 30-45 min |
| 7. Logout/login | 1 min |
| 8. Personal tools | 5-10 min |
| 9. Data restore | 10-20 min |
| **Total** | **~2 hours** |

First install from scratch: 6+ hours (manually fixing everything).
With this setup: ~2 hours (most time is downloads).

---

## What you absolutely must not forget

Before starting your next install, verify these are on GitHub:

- [ ] `z13-cachyos-setup.sh` (Z13 hardware)
- [ ] `cachyos-postinstall.sh` (apps + KDE menu)
- [ ] `Arch-tools/` (1337codes — already public)
- [ ] Joplin backup (JEX)
- [ ] SSH keys backup
- [ ] OpenVPN configs backup
- [ ] BurpSuite Pro installer + license
- [ ] OSCP.tar.gz or equivalent training data

Without these = manually start over.
With these = 2 hours to working daily-driver.

---

## License

MIT
