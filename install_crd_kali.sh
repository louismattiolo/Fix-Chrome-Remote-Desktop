#!/bin/bash

# --------------------------------------------------------
# Chrome Remote Desktop Installer/Fix for Kali Linux
# Uses xfce4-session (Kali-specific)
# --------------------------------------------------------

USER_NAME=$(whoami)
SESSION_FILE="/home/$USER_NAME/.chrome-remote-desktop-session"

echo "==============================="
echo " Chrome Remote Desktop - Kali"
echo "==============================="

sleep 1

# Install XFCE (Kali uses XFCE by default, but ensure it is present)
echo "[+] Installing XFCE..."
sudo apt update
sudo apt install -y xfce4 xfce4-session xfce4-goodies

# Install CRD
if ! command -v chrome-remote-desktop >/dev/null 2>&1; then
    echo "[+] Installing Chrome Remote Desktop..."
    wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
    sudo apt install -y ./chrome-remote-desktop_current_amd64.deb
else
    echo "[+] CRD already installed."
fi

# Create session file (Kali uses 'xfce4-session' instead of 'startxfce4')
echo "[+] Creating CRD session file..."

cat > "$SESSION_FILE" <<EOF
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec /usr/bin/xfce4-session
EOF

chmod +x "$SESSION_FILE"
sudo chown $USER_NAME:$USER_NAME "$SESSION_FILE"

# Restart CRD service
echo "[+] Restarting CRD service..."
sudo systemctl restart chrome-remote-desktop@$USER_NAME

echo "====================================================="
echo " Kali setup complete!"
echo " Go to: https://remotedesktop.google.com/headless"
echo " Copy the host registration command and paste it here."
echo "====================================================="
