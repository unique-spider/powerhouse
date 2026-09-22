#!/bin/bash
# Power House installer — run as root:  sudo ./install.sh   (from ~/Work/powerhouse)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
U=${SUDO_USER:?run with sudo as your normal user, not directly as root (SUDO_USER is unset)}
HOME_U=$(getent passwd "$U" | cut -d: -f6)

# Re-exec from a root-owned, freshly extracted snapshot of the exact commit on disk, instead of
# installing straight out of this checkout. The checkout directory is writable by $U, so any
# same-UID process could otherwise replace a file here in the gap between this script starting
# and each `install` line below reading it -- root would then install whatever was swapped in.
# `git archive` pulls bytes straight from git's content-addressed object store keyed to the
# commit hash, so nothing written to the working tree after this point can change what gets
# extracted, and /run/powerhouse-install is root-owned (0700) so $U can't touch it either.
if [[ -z "${POWERHOUSE_SNAPSHOT_DONE:-}" ]]; then
  D=$(cd "$(dirname "$0")" && pwd)
  git -C "$D" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "install.sh must be run from a git checkout (refusing to trust an unpinned tree)" >&2; exit 1; }
  REF=$(git -C "$D" rev-parse HEAD)
  mkdir -p /run/powerhouse-install && chmod 0700 /run/powerhouse-install
  SNAP=$(mktemp -d /run/powerhouse-install/powerhouse.XXXXXX)
  git -C "$D" archive "$REF" | tar --no-same-owner -x -C "$SNAP"
  exec env POWERHOUSE_SNAPSHOT_DONE=1 SUDO_USER="$U" bash "$SNAP/install.sh"
fi

D=$(cd "$(dirname "$0")" && pwd)
echo "== root-side files"
install -m 0755 "$D/governor/powerhouse-governor" /usr/local/bin/powerhouse-governor
install -m 0755 "$D/governor/powerhouse-apply"    /usr/local/bin/powerhouse-apply
install -m 0755 "$D/governor/powerhouse-unlock"   /usr/local/bin/powerhouse-unlock
if [[ -f /usr/local/bin/kbdlight-helper && ! -f /usr/local/bin/kbdlight-helper.setuid.bak ]]; then
  cp -a /usr/local/bin/kbdlight-helper /usr/local/bin/kbdlight-helper.setuid.bak; chmod 0700 /usr/local/bin/kbdlight-helper.setuid.bak
fi
echo "== building kbdlight-helper from source (no prebuilt binary is shipped -- see governor/kbdlight-helper.c)"
command -v "${CC:-cc}" >/dev/null || { echo "no C compiler found (set \$CC, or install gcc/clang)" >&2; exit 1; }
"${CC:-cc}" -O2 -Wall -Wextra -o /usr/local/bin/kbdlight-helper "$D/governor/kbdlight-helper.c"
chmod 0755 /usr/local/bin/kbdlight-helper      # NOT setuid any more
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
# Only ever clean up a snapshot we made ourselves under /run/powerhouse-install -- never the
# original checkout, even if something upstream of this line ever changes how $D is derived.
[[ "$D" == /run/powerhouse-install/* ]] && rm -rf "$D"
exit 0
