#!/bin/bash
# Power House installer — run as root:  sudo ./install.sh   (from ~/Work/powerhouse)
set -euo pipefail
U=${SUDO_USER:?run with sudo as your normal user, not directly as root (SUDO_USER is unset)}
HOME_U=$(getent passwd "$U" | cut -d: -f6); D=$(cd "$(dirname "$0")" && pwd)
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
echo "== root-side files"
install -m 0755 "$D/governor/powerhouse-governor" /usr/local/bin/powerhouse-governor
install -m 0755 "$D/governor/powerhouse-apply"    /usr/local/bin/powerhouse-apply
install -m 0755 "$D/governor/powerhouse-unlock"   /usr/local/bin/powerhouse-unlock
if [[ -f /usr/local/bin/kbdlight-helper && ! -f /usr/local/bin/kbdlight-helper.setuid.bak ]]; then
  cp -a /usr/local/bin/kbdlight-helper /usr/local/bin/kbdlight-helper.setuid.bak; chmod 0700 /usr/local/bin/kbdlight-helper.setuid.bak
fi
install -m 0755 "$D/governor/kbdlight-helper" /usr/local/bin/kbdlight-helper      # NOT setuid any more
install -m 0644 "$D/polkit/com.uniquespider.powerhouse.policy" /usr/share/polkit-1/actions/
install -m 0644 "$D/systemd/powerhouse-governor.service" /etc/systemd/system/
mkdir -p /etc/powerhouse /var/lib/powerhouse /usr/local/share/powerhouse
install -m 0644 "$D/governor/limits.default.json" /usr/local/share/powerhouse/limits.default.json
printf '{"user": "%s", "tick": 3}\n' "$U" > /etc/powerhouse/governor.json
[[ -f /etc/powerhouse/limits.json ]] || cp "$D/governor/limits.default.json" /etc/powerhouse/limits.json
python3 - <<'PY'   # seed the crash lock with the offsets live at the 2026-08-28 23:19 crash
import json; p="/etc/powerhouse/limits.json"; l=json.load(open(p)); c=l.setdefault("crash_locked", {})
c.setdefault("gpc", 200); c.setdefault("mem", 600); json.dump(l, open(p, "w"), indent=1)
PY
echo "== sudoers: narrow victus-priv to safe/read-only operations (password for everything else)"
sed "s/@USER@/$U/g" "$D/governor/sudoers.victus-plugin" > /etc/sudoers.d/victus-plugin
chmod 0440 /etc/sudoers.d/victus-plugin; visudo -cf /etc/sudoers.d/victus-plugin
echo "== start governor"
systemctl daemon-reload; systemctl enable powerhouse-governor.service >/dev/null; systemctl restart powerhouse-governor.service; sleep 2
systemctl --no-pager --lines=5 status powerhouse-governor || true
echo "== user-side files (as $U)"
sudo -u "$U" env XDG_RUNTIME_DIR="/run/user/$(id -u "$U")" bash -c "
  install -m 0755 '$D/bin/powerhouse' '$D/bin/powerhouse-audiod' '$D/bin/powerhouse-ai' '$HOME_U/.local/bin/'
  mkdir -p '$HOME_U/.config/systemd/user' '$HOME_U/.config/powerhouse' '$HOME_U/.local/state/powerhouse'
  install -m 0644 '$D/systemd/powerhouse-audiod.service' '$D/systemd/powerhouse-ai.service' '$D/systemd/powerhouse-ai.timer' '$HOME_U/.config/systemd/user/'
  [[ -f '$HOME_U/.config/powerhouse/audio.json' ]] || cp '$D/governor/audio.default.json' '$HOME_U/.config/powerhouse/audio.json'
  [[ -f '$HOME_U/.config/powerhouse/ai.json' ]] || cp '$D/governor/ai.default.json' '$HOME_U/.config/powerhouse/ai.json'
  target='$HOME_U/.config/omarchy/plugins/uniquespider.powerhouse'
  if [[ \"\$(readlink -f '$D')\" != \"\$(readlink -f \"\$target\" 2>/dev/null)\" ]]; then
    rm -rf \"\$target\"; mkdir -p \"\$target\"
    cp '$D/manifest.json' \"\$target/\"; cp -r '$D/plugin' \"\$target/plugin\"
  fi   # already in place: this checkout IS the plugin dir (installed via omarchy plugin add)
  systemctl --user daemon-reload
  systemctl --user enable --now powerhouse-audiod.service powerhouse-ai.timer
"
echo "== done. Enable the bar widget:  omarchy-plugin-enable uniquespider.powerhouse center"
