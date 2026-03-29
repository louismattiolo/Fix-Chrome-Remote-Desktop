#!/bin/bash

# Chrome Remote Desktop - Install / Fix for Ubuntu
# Usage:
#   sudo bash crd_ubuntu.sh          (fresh install)
#   sudo bash crd_ubuntu.sh --fix    (purge and reinstall)

set -euo pipefail

# ── Checks ───────────────────────────────────────────────────

if [[ "$EUID" -ne 0 ]]; then
    echo "Run as root: sudo bash crd_ubuntu.sh [--fix]"
    exit 1
fi

USER_NAME="${SUDO_USER:-}"
if [[ -z "$USER_NAME" ]]; then
    echo "Could not detect real user. Use sudo, not root directly."
    exit 1
fi

MODE="${1:-install}"
if [[ "$MODE" != "install" && "$MODE" != "--fix" ]]; then
    echo "Unknown argument. Usage: sudo bash crd_ubuntu.sh [--fix]"
    exit 1
fi

# ── Variables ────────────────────────────────────────────────

HOME_DIR="/home/$USER_NAME"
SESSION_FILE="$HOME_DIR/.chrome-remote-desktop-session"
CONFIG_DIR="$HOME_DIR/.config/chrome-remote-desktop"
DEB="/tmp/chrome-remote-desktop_current_amd64.deb"
SERVICE="chrome-remote-desktop@$USER_NAME"
USER_ID=$(id -u "$USER_NAME")

# ── Safety trap ───────────────────────────────────────────────
#
# Runs on exit (normal or crash). Ensures nothing in the user's home
# directory is left owned by root, which causes the login loop on ESXi.
# Only prints and acts if it actually finds something to fix.

trap '
    BAD=$(find "$HOME_DIR" -not -user "$USER_NAME" 2>/dev/null)
    if [[ -n "$BAD" ]]; then
        echo "[!] Found root-owned files in home directory - fixing ownership..."
        find "$HOME_DIR" -not -user "$USER_NAME" -exec chown "$USER_NAME:$USER_NAME" {} +
    fi
' EXIT

# ── Fix mode: purge existing install ─────────────────────────

if [[ "$MODE" == "--fix" ]]; then
    read -r -p "This will purge CRD and wipe its config. Continue? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && echo "Aborted." && trap - EXIT && exit 0

    systemctl stop "$SERVICE" 2>/dev/null || true
    apt purge -y chrome-remote-desktop 2>/dev/null || true
    rm -rf "$CONFIG_DIR" "$SESSION_FILE" "$SESSION_FILE.bak" "$DEB"
    rm -f /tmp/.X[2-9][0-9]-lock /tmp/.X1[0-9][0-9]-lock

    echo "Purge done. Reinstalling..."
fi

# ── Install ──────────────────────────────────────────────────

apt update
apt install -y xfce4 xfce4-goodies

if ! command -v chrome-remote-desktop >/dev/null 2>&1; then
    wget -q --show-progress -O "$DEB" \
        https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
    apt install -y "$DEB"
    rm -f "$DEB"
fi

# Install dbus-user-session so snap apps work in CRD (fixes cgroup session bus issue)
apt install -y dbus-user-session

# Enable linger so user systemd instance persists across CRD sessions
loginctl enable-linger "$USER_NAME"

# Ensure group exists (postinst race condition can leave it missing) then add user
if ! getent group chrome-remote-desktop > /dev/null; then
    groupadd chrome-remote-desktop
fi
usermod -a -G chrome-remote-desktop "$USER_NAME"

# ── Session file ─────────────────────────────────────────────
#
# Snap apps (Firefox, VSCode, etc.) need two things inside a CRD session:
#
#   1. XDG_RUNTIME_DIR=/run/user/<uid>  — tells snap where its socket lives.
#      Without this snap can't find snapd-session-agent.socket and all snap
#      apps fail with an I/O error.
#
#   2. DBUS_SESSION_BUS_ADDRESS pointing at the EXISTING systemd user bus
#      socket (/run/user/<uid>/bus) — snap validates that the calling process
#      is inside the correct systemd cgroup scope. Spawning a NEW bus daemon
#      (e.g. via dbus-run-session) fails that check. Pointing at the already-
#      running systemd bus passes it, so any snap app works without extra config.

# Back up last working session file before overwriting
if [[ -f "$SESSION_FILE" ]]; then
    cp "$SESSION_FILE" "$SESSION_FILE.bak"
    echo "[+] Backed up existing session file to $SESSION_FILE.bak"
fi

cat > "$SESSION_FILE" <<EOF
#!/bin/bash
export XDG_RUNTIME_DIR=/run/user/${USER_ID}
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus"
export CHROME_REMOTE_DESKTOP_DEFAULT_DESKTOP_SIZES=1920x1080
exec /usr/bin/startxfce4
EOF

# Validate session file syntax before going any further
if ! bash -n "$SESSION_FILE"; then
    echo "ERROR: Session file has syntax errors. Restoring backup and aborting."
    [[ -f "$SESSION_FILE.bak" ]] && cp "$SESSION_FILE.bak" "$SESSION_FILE"
    exit 1
fi

chmod +x "$SESSION_FILE"
chown "$USER_NAME:$USER_NAME" "$SESSION_FILE"

mkdir -p "$CONFIG_DIR"
chown -R "$USER_NAME:$USER_NAME" "$CONFIG_DIR"

# ── Ownership audit ───────────────────────────────────────────
#
# Explicitly verify nothing in home is root-owned before we restart CRD.
# The EXIT trap also does this, but running it here means we catch it
# before the service restarts rather than only on script exit.

echo "[+] Auditing home directory ownership..."
find "$HOME_DIR" -not -user "$USER_NAME" -exec chown "$USER_NAME:$USER_NAME" {} \;

# ── Start service ─────────────────────────────────────────────

systemctl daemon-reload
systemctl restart "$SERVICE" 2>/dev/null \
    || echo "Note: CRD service not ready yet - normal before registration."

# ── Done ──────────────────────────────────────────────────────

echo ""
echo "Done. Next steps:"
echo "  1. Log OUT of the VM console (black screen if you don't)"
echo "  2. Go to https://remotedesktop.google.com/headless"
echo "  3. Skip the .deb download - already installed"
echo "  4. Paste the SSH command here and set a PIN"
echo ""
