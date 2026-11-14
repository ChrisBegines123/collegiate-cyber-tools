#!/bin/bash

echo "This is an untested script, be careful"
TEMP="$(mktemp -d)"
cd "$TEMP" || exit 37

git clone https://github.com/rvaiya/keyd
cd keyd || exit 37
make && sudo make install

if [[ -n "$(which wl-paste)" ]]; then
  echo "wayland clipboard found, setting up service"
  touch /etc/keyd/clip
  chmod 720 /etc/keyd/clip
  chown root:wheel /etc/keyd/clip

  sudo tee /etc/systemd/user/keyd-clip.service >/dev/null <<'EOF'
[Unit]
After=graphical-session.target
Description=Mirror clipboard to keyd
PartOf=graphical-session.target

[Service]
ExecStart=wl-paste --type text --watch sh -c "[ "$CLIPBOARD_STATE" = "sensitive" ] && exit 0
cat > /etc/keyd/clip"
Restart=on-failure
EOF

  # this is the keyd config that captures ctr+alt+v
  sudo tee "/etc/keyd/default.conf" >/dev/null <<'EOF'
[ids]
*
[control+alt]
v=command(keyd input -t 10 "$(cat /etc/keyd/clip)")
EOF

  cat >"$HOME/.local/bin/keyd-clip-toggle" <<'EOF'
if systemctl --user is-active --quiet keyd-clip; then
  systemctl --user stop --quiet keyd-clip
else
  systemctl --user start --quiet keyd-clip
fi
EOF

else
  echo "could not find wl-clipboard, I don't know how to proceed"
  exit 37
fi
if [[ -n "$(which waybar)" ]]; then
  echo "Found waybar, adding a status script"
  cat >"$HOME/.local/bin/keyd-clip-status" <<'EOF'
if systemctl --user is-active --quiet keyd-clip; then
  echo '{"text":"","tooltip":"Clipboard mirror active (click to stop)","class":"on"}'
else
  echo '{"text":"","tooltip":"Clipboard mirror stopped (click to start)","class":"off"}'
fi
EOF
  echo "This is my best guess as to what you should add to waybar's config.jsonc"
  # I am checking every 30 seconds bcs this doesn't need to be responsive
  cat <<'EOF'
      "custom/keyd-clip": {
        "exec": "keyd-clip-status",
        "return-type": "json",
        "interval": 30,
        "signal": 9,
        "on-click": "keyd-clip-toggle"
    },
EOF

  echo "This is my best guess for what you want in your style.css"
  cat <<'EOF'
#custom-keyd-clip {
  padding: 0 10px;
  font-weight: 900;
  background-color: #794d20;
  color: #1e1e2e; 
}
#custom-keyd-clip:hover {
    background-color: #65401b;
}
EOF

fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Note: add ~/.local/bin to your PATH" >&2 ;;
esac
sudo systemctl enable --now keyd
systemctl --user daemon-reload
echo "Installation magically did not fail. You can toggle keyd-clip on and off."
echo "You can check status with systemctl status --user "
