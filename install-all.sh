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
trap 'rm -f "$DEPS_DIR"/*.tar "$ROOT_SCRIPT" 2>/dev/null || true' EXIT

# Every prerequisite is pinned to an exact, reviewed commit -- including
# Batuhan4/victus-control, which is a THIRD PARTY's repository, not mine.
# Without a pin, whatever that maintainer (or any of us) next pushes to the
# default branch would run as root on every install/re-run with no review at
# all. Bumping a pin here is a deliberate, visible, reviewable change to this
# file -- never done implicitly by `git pull`.
VICTUS_CONTROL_URL="https://github.com/Batuhan4/victus-control.git"
VICTUS_CONTROL_REF="5ec943dbdbc24f81f6cad26b2c2acadd2388c6f5"   # 2026-07-22
VICTUS_TOOLKIT_URL="https://github.com/unique-spider/victus-toolkit.git"
VICTUS_TOOLKIT_REF="5e128dd35d1e4a173b7d6f95a2fe16c37f1e1ca1"   # 2026-08-29
HPWMI_URL="https://github.com/unique-spider/hp-wmi-victus-8bb1.git"
HPWMI_REF="89ecbadd6e55033505308ef7bae1fb706b9d3017"            # 2026-08-29

clone_pinned() {
  local url=$1 ref=$2 dir=$3
  if [[ -d "$dir/.git" ]]; then
    echo "== fetching $(basename "$dir")"
    git -C "$dir" fetch --quiet origin
  else
    echo "== cloning $(basename "$dir")"
    git clone --quiet "$url" "$dir"
  fi
  git -C "$dir" checkout --quiet "$ref"
  local got; got=$(git -C "$dir" rev-parse HEAD)
  [[ "$got" == "$ref" ]] || { echo "FATAL: $(basename "$dir") did not land on the pinned commit ($ref), got $got -- refusing to run unreviewed code" >&2; exit 1; }
  echo "   -> $(basename "$dir") @ ${ref:0:12}"
  # Freeze this exact, verified commit into a tarball now, while still unprivileged. The
  # elevated step below extracts this into a fresh root-owned directory and runs only from
  # there -- `git archive` reads bytes straight from git's content-addressed object store keyed
  # to $ref, so nothing written to $dir's working tree after this point (by any same-UID
  # process) can change what ends up installed as root.
  git -C "$dir" archive "$ref" -o "$dir.tar"
}

echo "Power House -- one-click install"
echo "This clones 3 prerequisite repos (all public, linked from the README,"
echo "each pinned to an exact commit -- see the comment above for why) into"
echo "  $DEPS_DIR"
echo "then runs every root-owned install step behind one authentication dialog,"
echo "each one extracted fresh from its pinned commit into a root-owned snapshot"
echo "first (see 'How the root access actually works' in the README)."
echo "Nothing here is hidden -- read any of these scripts first if you want to."
echo

clone_pinned "$VICTUS_CONTROL_URL" "$VICTUS_CONTROL_REF" "$DEPS_DIR/victus-control"
clone_pinned "$VICTUS_TOOLKIT_URL" "$VICTUS_TOOLKIT_REF" "$DEPS_DIR/victus-toolkit"

WANT_HPWMI=0
read -rp "Also build hp-wmi-victus-8bb1 (kernel-module patch) for GPU CTGP/PPAB + CPU power-limit WMI control? [y/N] " ans
if [[ "${ans,,}" == y* ]]; then
  WANT_HPWMI=1
  clone_pinned "$HPWMI_URL" "$HPWMI_REF" "$DEPS_DIR/hp-wmi-victus-8bb1"
fi

echo
echo "== one authentication prompt for every root step below"
ROOT_SCRIPT=$(mktemp)
{
  echo "set -euo pipefail"
  echo "export SUDO_USER=$(printf '%q' "$USER")"
  # Every payload below is extracted from its verified tarball into a fresh, root-owned (0700)
  # directory under /run before anything reads or executes it -- never run in place from
  # $DEPS_DIR, which $USER can still write to even after the pin check above.
  echo 'mkdir -p /run/powerhouse-install && chmod 0700 /run/powerhouse-install'
  # $d/$1 below are single-quoted on purpose: they must expand when the generated ROOT_SCRIPT
  # runs (as root), not now, while we're still building that script as $USER.
  # shellcheck disable=SC2016
  echo 'snapshot() { local d; d=$(mktemp -d /run/powerhouse-install/snap.XXXXXX); tar --no-same-owner -xf "$1" -C "$d"; echo "$d"; }'
  echo "echo '-- victus-control (fan backend)'"
  echo "VC_DIR=\$(snapshot $(printf '%q' "$DEPS_DIR/victus-control.tar"))"
  echo "cd \"\$VC_DIR\" && ./install.sh"
  echo "echo '-- victus-toolkit (victus-priv, victusctl, victus-fanctl)'"
  echo "VT_DIR=\$(snapshot $(printf '%q' "$DEPS_DIR/victus-toolkit.tar"))"
  echo "cd \"\$VT_DIR\" && ./install.sh"
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
    echo "  HPWMI_DIR=\$(snapshot $(printf '%q' "$DEPS_DIR/hp-wmi-victus-8bb1.tar"))"
    echo "  cd \"\$VT_DIR\" && HP_WMI_KBD_DIR=\"\$HPWMI_DIR\" ./install-hpwmi.sh"
    echo "  cd \"\$VT_DIR\" && ./setup-kbd-led.sh"
    # install-hpwmi.sh builds kbd-light inside $HPWMI_DIR, which is root-owned 0700 -- copy it
    # back out to the user-writable deps dir (chowned to $USER) so the unprivileged step below,
    # which still expects to find it at its original pre-snapshot path, can read it.
    echo "  [[ -f \"\$HPWMI_DIR/kbd-light\" ]] && install -o $(printf '%q' "$USER") -m 0755 \"\$HPWMI_DIR/kbd-light\" $(printf '%q' "$DEPS_DIR/hp-wmi-victus-8bb1/kbd-light")"
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
  # install.sh snapshots and re-execs itself the same way (it has to: it's also runnable
  # directly via `sudo ./install.sh`, outside this script), so $REPO_DIR here is safe to pass
  # as-is -- it's never read again after that self-snapshot.
  echo "cd $(printf '%q' "$REPO_DIR") && ./install.sh"
  echo "rm -rf /run/powerhouse-install"
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
