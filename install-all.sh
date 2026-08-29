#!/bin/bash
# Power House — one-click installer.
#
# Clones the 3 prerequisite repos (or updates them if already cloned), asks
# the one genuinely optional question this project has (build the hp-wmi
# kernel-module patch?), then runs every root-owned install step behind a
# SINGLE pkexec authentication dialog -- one password prompt, not four.
#
# Run as your normal user (it elevates itself once, via pkexec):
#   ./install-all.sh
set -euo pipefail

[[ $EUID -ne 0 ]] || { echo "run this as your normal user, not root/sudo -- it elevates itself once via pkexec" >&2; exit 1; }
command -v pkexec >/dev/null || { echo "pkexec not found (polkit not installed?)" >&2; exit 1; }
command -v git >/dev/null || { echo "git not found" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="${POWERHOUSE_DEPS_DIR:-$HOME/.local/share/powerhouse-deps}"
mkdir -p "$DEPS_DIR"

clone_or_update() {
  local url=$1 dir=$2
  if [[ -d "$dir/.git" ]]; then
    echo "== updating $(basename "$dir")"
    git -C "$dir" pull --ff-only --quiet
  else
    echo "== cloning $(basename "$dir")"
    git clone --quiet "$url" "$dir"
  fi
}

echo "Power House -- one-click install"
echo "This clones 3 prerequisite repos (all public, linked from the README) into"
echo "  $DEPS_DIR"
echo "then runs every root-owned install step behind one authentication dialog."
echo "Nothing here is hidden -- read any of these scripts first if you want to."
echo

clone_or_update "https://github.com/Batuhan4/victus-control.git"      "$DEPS_DIR/victus-control"
clone_or_update "https://github.com/unique-spider/victus-toolkit.git" "$DEPS_DIR/victus-toolkit"

WANT_HPWMI=0
read -rp "Also build hp-wmi-victus-8bb1 (kernel-module patch) for GPU CTGP/PPAB + CPU power-limit WMI control? [y/N] " ans
if [[ "${ans,,}" == y* ]]; then
  WANT_HPWMI=1
  clone_or_update "https://github.com/unique-spider/hp-wmi-victus-8bb1.git" "$DEPS_DIR/hp-wmi-victus-8bb1"
fi

echo
echo "== one authentication prompt for every root step below"
ROOT_SCRIPT=$(mktemp)
trap 'rm -f "$ROOT_SCRIPT"' EXIT
{
  echo "set -euo pipefail"
  echo "export SUDO_USER=$(printf '%q' "$USER")"
  echo "echo '-- victus-control (fan backend)'"
  echo "cd $(printf '%q' "$DEPS_DIR/victus-control") && ./install.sh"
  echo "echo '-- victus-toolkit (victus-priv, victusctl, victus-fanctl)'"
  echo "cd $(printf '%q' "$DEPS_DIR/victus-toolkit") && ./install.sh"
  if [[ $WANT_HPWMI -eq 1 ]]; then
    # A subshell's own `set -e` is silently suppressed by bash when that
    # subshell is used directly as an `if`/`!` condition -- a real bash
    # gotcha that would make failures here invisible. So: run the subshell
    # as a plain command with the OUTER script's errexit off, capture its
    # exit code explicitly, then re-enable errexit before branching on it.
    # This step is optional; the Power House install below is not, and must
    # still run even if this one fails.
    echo "set +e"
    echo "( set -e"
    echo "  echo '-- hp-wmi-victus-8bb1 (DKMS kernel module)'"
    echo "  cd $(printf '%q' "$DEPS_DIR/victus-toolkit") && HP_WMI_KBD_DIR=$(printf '%q' "$DEPS_DIR/hp-wmi-victus-8bb1") ./install-hpwmi.sh"
    echo "  cd $(printf '%q' "$DEPS_DIR/victus-toolkit") && ./setup-kbd-led.sh"
    echo ")"
    echo "hpwmi_rc=\$?"
    echo "set -e"
    echo "if [[ \$hpwmi_rc -ne 0 ]]; then"
    echo "  echo 'WARNING: hp-wmi-victus-8bb1 step failed -- continuing without it.' >&2"
    echo "  echo '         GPU CTGP/PPAB and CPU power-limit WMI control wont work; everything' >&2"
    echo "  echo '         else will. Re-run install-hpwmi.sh by hand later to retry.' >&2"
    echo "fi"
  fi
  echo "echo '-- Power House (governor, polkit, systemd, bar plugin)'"
  echo "cd $(printf '%q' "$REPO_DIR") && ./install.sh"
} > "$ROOT_SCRIPT"
chmod +x "$ROOT_SCRIPT"
pkexec bash "$ROOT_SCRIPT"

if [[ $WANT_HPWMI -eq 1 && -f "$DEPS_DIR/hp-wmi-victus-8bb1/kbd-light" ]]; then
  echo "== installing kbd-light (unprivileged, your own ~/.local/bin)"
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$DEPS_DIR/hp-wmi-victus-8bb1/kbd-light" "$HOME/.local/bin/kbd-light"
fi

echo
echo "== enabling the bar widget"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin enable uniquespider.powerhouse --section center 2>/dev/null \
    || omarchy-plugin-enable uniquespider.powerhouse center 2>/dev/null \
    || true
fi

cat <<'EOF'

Done. Two things this script deliberately does NOT do for you:
  - The AI governor needs YOUR OWN Claude Code login (a real browser
    sign-in, can't be scripted) -- see the README's "Set up the AI
    governor" section.
  - kbd-audioctl and victus-guardian aren't published yet, so the Keys
    tab's audio-reactive controls and the Guard tab's Insights button
    will error until those land. Everything else works.
EOF
