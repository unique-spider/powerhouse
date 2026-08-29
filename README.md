# Power House — governed laptop control for Omarchy (HP Victus 15)

> **⚠️ Read before installing.** This is a root-privileged system, not a
> sandboxed widget:
> - Verified only on **HP Victus 15-fa1xxx, board `8BB1`**. It pokes EC
>   registers directly through Super I/O ports 0x2E/0x2F, writes CPU MSR
>   0x610, and issues GPU clock/power-limit calls. On different hardware the
>   EC register map and MSR behavior may not match — review the source
>   (especially `governor/powerhouse-governor`) before running this on
>   anything else.
> - The governor daemon runs as **root** at boot. `powerhouse-apply` requires
>   your password every time (polkit `auth_admin`) for any tweak; it's a
>   deliberate friction point, not a bug.
> - `powerhouse-ai` calls Claude Code with your own API usage/budget on a
>   timer (default: login + every 30 min, capped at 8 runs / 120k tokens /
>   2 Opus runs per rolling 5 h — see `~/.config/powerhouse/ai.json`). Disable
>   it (`systemctl --user disable --now powerhouse-ai.timer`) if you don't
>   want an LLM reviewing your hardware logs and tightening caps on its own.
> - No warranty. This grew out of chasing real hard crashes on one specific
>   laptop (see below) — it is offered as-is, not as a certified-safe product.

One bar plugin with a dashboard per domain, a root **governor** that owns every
dangerous knob, and an **AI governor** (Claude Code headless) that learns from
incidents. Built 2026-08-28 after a run of hard crashes.

## Prerequisites

Install in this order — Power House orchestrates these, it doesn't replace them:

1. [`victus-control`](https://github.com/Batuhan4/victus-control) (upstream) —
   fan backend socket (`victus_backend.sock`) the governor's fan calls go through.
2. [`hp-wmi-kbd`](https://github.com/unique-spider/hp-wmi-kbd) — patched
   `hp-wmi` DKMS module (board `8BB1`) for GPU CTGP/PPAB and CPU-PL WMI paths.
   Skip if you don't need those.
3. [`victus-toolkit`](https://github.com/unique-spider/victus-toolkit) —
   `victus-priv`, `victus-gpu-nvml`, and friends that the governor and
   sudoers rule (`governor/sudoers.victus-plugin`) call into.

## Why it exists (the evidence)

* 4–5 hard crashes/day since 2026-08-26 16:34 — the moment a setuid helper
  started driving the keyboard backlight by poking EC RAM through Super I/O
  ports 0x2E/0x2F from **two separate processes** (a PWM daemon and the hotkey
  on/off helper). The 4-step address/data sequence is not atomic; interleaved
  writers land bytes on random EC registers. The helper's own source already
  mentioned "phantom keys" from continuous PWM — the same corruption.
* 3 of the 4 crashes on Aug 28 happened with the GPU idle at stock clocks and the
  CPU at ~50 °C. The +200/+600 MHz GPU offset was only active during the last one.
* Two earlier power-cuts landed seconds after direct MSR 0x610 writes.

## Architecture

| Piece | Runs as | Job |
|---|---|---|
| `powerhouse-governor` | root, `powerhouse-governor.service` (every boot) | **EC arbiter** (single lock, register whitelist `0x1805`, write-rate budget with trip), keyboard soft-PWM, 3 s enforcement of `/etc/powerhouse/limits.json`, crash memory (`/var/lib/powerhouse/{last-state.json,incidents.jsonl,events.jsonl}`), applies `desired.json` clamped to caps |
| `powerhouse-apply` | root via **pkexec** (polkit `auth_admin` → password every time) | the only writer of `desired.json`; the only path that can **loosen** caps (hard bounds: core ≤ +300, mem ≤ +1500, PL ≤ 45/115 W) |
| `kbdlight-helper` (shim) | user, not setuid | same CLI as the old helper, but only forwards duty values to the governor socket |
| `powerhouse-audiod` | user service | per-app routing: excluded apps bypass the `kbd-mix` sink the keys listen to |
| `powerhouse-ai` | user timer (login + 30 min) | Claude Code `-p`: Sonnet 5 reviews, Opus 5 after a crash; may only **tighten**; rolling 5 h budget (8 runs / 120k tokens / 2 Opus) |
| `powerhouse` | user CLI | status JSON for the panel; actions |
| `plugin/` | Omarchy shell | tabs Keys · OC · Fan · Power · Guard · Batt · Sys · Gov |

Thermal guard (spike-aware): CPU ≥ 88 °C, GPU ≥ 83 °C or a rise ≥ 12 °C within one
3-s tick ⇒ fans max, CPU PL 35/55 W, GPU offsets cleared; CPU ≥ 94 °C ⇒ PL 20/35 W +
low-power profile. Released after 60 s below 75 °C. Each event is an incident and
flags a Sonnet review.

Two locks on overclocking: (1) every change asks for the password (polkit
`com.uniquespider.powerhouse.tweak`); (2) offsets that were live at a hard crash are
recorded in `limits.json` → `crash_locked` and `loosen` refuses to reach them;
`powerhouse-unlock` (its own polkit action with a crash warning) is the only way
to release a lock. Seeded with +200/+600 from the 2026-08-28 23:19 crash.
The Guard tab shows a merged timeline (guardian alerts, governor incidents/events, AI runs).

Crash-aware tightening: on boot, if the clean-shutdown marker is missing, the
last state is recorded as an incident, offsets caps drop 50 MHz below whatever
was active, PL caps return to stock, keyboard PWM budget halves, and an Opus 5
review is requested.

## Install

Via the Omarchy plugin marketplace (clones straight into
`~/.config/omarchy/plugins/uniquespider.powerhouse/`):

```sh
omarchy plugin add https://github.com/unique-spider/powerhouse.git --yes
sudo ~/.config/omarchy/plugins/uniquespider.powerhouse/install.sh   # one password
omarchy plugin enable uniquespider.powerhouse --section center
```

Or from a manual clone/dev checkout anywhere:

```sh
git clone https://github.com/unique-spider/powerhouse.git && cd powerhouse
sudo ./install.sh
omarchy-plugin-enable uniquespider.powerhouse center
omarchy-plugin-disable anbuselvan.victus       # optional: the old widget
```

Either way, `install.sh` must be run with `sudo` as your normal user (not
directly as `root`) — it reads `$SUDO_USER` and fails loudly if that's unset.
It also narrows `/etc/sudoers.d/victus-plugin` so only read-only /
stock-restoring `victus-priv` calls stay passwordless.

## Files

* `/etc/powerhouse/limits.json` — enforced caps (`source` says who set them)
* `/etc/powerhouse/desired.json` — what you asked for (via pkexec)
* `/var/lib/powerhouse/` — governor memory
* `~/.config/powerhouse/{audio,ai}.json` — exclusions, AI models & budget
* `~/.local/state/powerhouse/{lessons.md,usage.jsonl,ai-runs.jsonl,last-*.md}` — AI memory and consumption

## Testing done (dry-run, `POWERHOUSE_PREFIX=…`)

enforcement (offset 200/600 & PL2 150 → stock within one tick), shim pwm/on/off,
SIGKILL → next start logs `boot.crash_detected`, tightens caps and sets the AI flag,
over-cap `desired.json` clamped, AI proposal accepted only when tighter (with floors),
SIGTERM → marker → `boot.clean`; audio router moves a fake app both ways;
one real Sonnet 5 review with usage accounting.
