#!/bin/bash

# --------------------------------------------------------
# Chrome Remote Desktop Installer/Fix for Ubuntu
# Uses XFCE and compatible session variables
# --------------------------------------------------------

USER_NAME=$(whoami)
SESSION_FILE="/home/$USER_NAME/.chrome-remote-desktop-session"

echo "==============================="
echo " Chrome Remote Desktop - Ubuntu"
echo "==============================="

sleep 1

# Install XFCE
echo "[+] Installing XFCE..."
sudo apt update
sudo apt install -y xfce4 xfce4-goodies

# Install Chrome Remote Desktop
if ! command -v chrome-remote-desktop >/dev/null 2>&1; then
    echo "[+] Installing Chrome Remote Desktop..."
    wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
    sudo apt install -y ./chrome-remote-desktop_current_amd64.deb
else
    echo "[+] CRD already installed."
fi

# Create session file
echo "[+] Creating CRD session file..."

cat > "$SESSION_FILE" <<EOF
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
export CHROME_REMOTE_DESKTOP_DEFAULT_DESKTOP_SIZES=1920x1080
exec /usr/bin/startxfce4
EOF

chmod +x "$SESSION_FILE"
sudo chown $USER_NAME:$USER_NAME "$SESSION_FILE"

# Restart CRD service
echo "[+] Restarting CRD service..."
sudo systemctl restart chrome-remote-desktop@$USER_NAME

echo "====================================================="
echo " Ubuntu setup complete!"
echo " Go to: https://remotedesktop.google.com/headless"
echo " Copy the host registration command and paste it here."
echo "====================================================="
