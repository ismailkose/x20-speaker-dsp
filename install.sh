#!/usr/bin/env bash
# x20-speaker-dsp installer — speaker DSP for the ASUS ROG Xbox Ally X20 (RC74XA) on SteamOS.
# Installs only into your home folder. No sudo, survives SteamOS updates.
#
#   ./install.sh                 install and turn on the default preset (xtc)
#   ./install.sh --preset wide   install and turn on another preset
#   ./install.sh --no-activate   install files only
#   ./install.sh --no-speaker-fix  don't add the speaker profile if the speakers are silent
#   ./install.sh --force         skip the device check (unsupported hardware!)
set -euo pipefail

VERSION="1.1.0"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pinned LSP Plugins build from the official Arch Linux archive (LGPL-3.0, not bundled here).
LSP_PKG="lsp-plugins-lv2-1.2.37-1-x86_64.pkg.tar.zst"
LSP_URL="https://archive.archlinux.org/packages/l/lsp-plugins-lv2/${LSP_PKG}"
LSP_SHA256="6386c3fecc40bf2eda355cb35dfb0dd10976c603a48daf01a5414a561801e90a"

DATA="$HOME/.local/share/x20-speaker-dsp"
LIB="$HOME/.local/lib/x20-speaker-dsp"
BIN="$HOME/.local/bin"
DROPIN_DIR="$HOME/.config/systemd/user/pipewire.service.d"
DROPIN="$DROPIN_DIR/x20-speaker-dsp.conf"
UNIT_DIR="$HOME/.config/systemd/user"
UCM_UNIT="x20-speaker-ucm.service"
FULL_FIX="https://github.com/hungarianhc/rog-ally-x20-steamos-speakers"

PRESET="xtc"; ACTIVATE=1; FORCE=0; SPKFIX=1
while [ $# -gt 0 ]; do
  case "$1" in
    --preset) PRESET="${2:?--preset needs a name}"; shift ;;
    --no-activate) ACTIVATE=0 ;;
    --no-speaker-fix) SPKFIX=0 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac; shift
done

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$HERE/presets/$PRESET.conf" ] || die "unknown preset '$PRESET' (see presets/)"
[ "$(id -u)" -ne 0 ] || die "run as your normal user, not root/sudo"

# ---------- 1. device check ----------
say "Checking device"
board="$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)"
vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
subsys=""
for d in /sys/bus/pci/devices/*; do
  [ "$(cat "$d/vendor" 2>/dev/null)" = "0x1022" ] && [ "$(cat "$d/device" 2>/dev/null)" = "0x15e2" ] || continue
  subsys="$(cat "$d/subsystem_vendor"):$(cat "$d/subsystem_device")"
done
echo "    board: ${board:-?}  vendor: ${vendor:-?}  audio subsystem: ${subsys:-?}"
if [ "$board" != "RC74XA" ] || [ "$subsys" != "0x1043:0x1954" ]; then
  if [ "$FORCE" = 1 ]; then
    warn "This is not an ROG Xbox Ally X20 (RC74XA). Continuing because of --force; the tuning is NOT made for this hardware."
  else
    die "This package is only for the ROG Xbox Ally X20 (RC74XA, audio subsystem 1043:1954, 2x TI TAS2783). The 2025 Ally X (RC73XA) has different audio hardware."
  fi
fi

# ---------- 2. software check ----------
say "Checking software"
for c in pw-cli pw-dump wpctl systemctl curl sha256sum tar python3 ldd amixer; do
  command -v "$c" >/dev/null || die "missing command: $c"
done
pwv="$(pipewire --version 2>/dev/null | sed -n 's/.*libpipewire \([0-9.]*\).*/\1/p' | head -1)"
wpv="$(wireplumber --version 2>/dev/null | sed -n 's/.*libwireplumber \([0-9.]*\).*/\1/p' | head -1)"
echo "    PipeWire ${pwv:-?}  WirePlumber ${wpv:-?}"
case "$wpv" in 0.4*|0.3*|"") die "WirePlumber 0.5 or newer is required (found '${wpv:-none}')";; esac

find_sink() {
  pw-dump 2>/dev/null | python3 -c '
import json,sys
try: objs=json.load(sys.stdin)
except Exception: objs=[]
for o in objs:
    p=(o.get("info") or {}).get("props") or {}
    n=p.get("node.name","")
    if p.get("media.class")=="Audio/Sink" and "amd_sdw" in n and "Speaker" in n:
        print(n); break'
}
wait_sink() { SINK=""; for _ in $(seq 1 "$1"); do SINK="$(find_sink)"; [ -n "$SINK" ] && return 0; sleep 1; done; return 1; }

# ---------- 3. speakers ----------
# PipeWire may still be starting (right after login or a restart).
say "Checking speakers"
if wait_sink 10; then
  echo "    speakers already working"
elif [ "$SPKFIX" = 0 ]; then
  die "Built-in speaker output not found (and --no-speaker-fix was given)."
else
  # Speakers silent. On SteamOS 3.10+ the kernel and amp firmware already support the X20;
  # only the speaker profile (ALSA UCM tas2783.conf) is missing. Older SteamOS needs the full fix.
  install -d "$DATA" "$BIN" "$UNIT_DIR"
  install -m755 "$HERE/bin/x20-dsp" "$BIN/x20-dsp"
  if ! "$BIN/x20-dsp" speaker-driver; then
    die "The speaker driver isn't loaded (the sound card doesn't report the TAS2783 amps).
      This SteamOS/kernel ($(uname -r)) doesn't support the X20 speakers out of the box.
      Update SteamOS to 3.10 or newer, or use the full speaker fix (needs sudo + reboot):
      $FULL_FIX"
  fi
  if [ -f /usr/share/alsa/ucm2/sof-soundwire/tas2783.conf ]; then
    die "Speaker driver and profile are both present, but PipeWire shows no speaker output.
      Try a reboot, then run ./install.sh again."
  fi
  say "Adding the X20 speaker profile (missing from this SteamOS version)"
  install -m644 "$HERE/ucm/tas2783.conf" "$DATA/tas2783.conf"
  install -m644 "$HERE/ucm/LICENSE.alsa-ucm-conf" "$DATA/LICENSE.alsa-ucm-conf"
  install -m644 "$HERE/ucm/$UCM_UNIT" "$UNIT_DIR/$UCM_UNIT"
  systemctl --user daemon-reload
  systemctl --user enable "$UCM_UNIT" >/dev/null 2>&1
  "$BIN/x20-dsp" speaker-profile --apply
  wait_sink 15 || die "Speaker profile added, but the speaker output still doesn't show up.
      Reboot and run ./install.sh again. If it stays silent, see $FULL_FIX"
  echo "    speakers working"
fi
echo "    speaker sink: $SINK"

# Conflicts: other speaker DSPs processing the same audio.
if pgrep -x easyeffects >/dev/null 2>&1; then
  warn "EasyEffects is running. Quit it (and disable its autostart) so audio isn't processed twice."
fi
for f in "$HOME"/.config/pipewire/pipewire.conf.d/*.conf; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" = "90-x20-dsp.conf" ] && continue
  if grep -q 'filter.smart' "$f" && grep -q "$SINK" "$f"; then
    warn "Another speaker filter is installed: $f — remove it to avoid double processing."
  fi
done

# ---------- 4. LSP plugins ----------
if [ -f "$LIB/lv2/lsp-plugins.lv2/lsp-plugins-lv2.so" ] && [ "$(cat "$LIB/lsp.sha256" 2>/dev/null)" = "$LSP_SHA256" ]; then
  say "LSP Plugins already installed"
else
  say "Downloading LSP Plugins (${LSP_PKG})"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fL --retry 3 -o "$tmp/$LSP_PKG" "$LSP_URL"
  echo "$LSP_SHA256  $tmp/$LSP_PKG" | sha256sum -c --status - || die "LSP package checksum mismatch — download aborted"
  # Optional: verify the Arch packager signature too, if the Arch keyring is available.
  if command -v gpg >/dev/null && [ -f /usr/share/pacman/keyrings/archlinux.gpg ] && curl -fsL -o "$tmp/$LSP_PKG.sig" "$LSP_URL.sig"; then
    export GNUPGHOME="$tmp/gnupg"; mkdir -m700 "$GNUPGHOME"
    gpg -q --import /usr/share/pacman/keyrings/archlinux.gpg 2>/dev/null || true
    if gpg --verify "$tmp/$LSP_PKG.sig" "$tmp/$LSP_PKG" 2>/dev/null; then echo "    Arch signature: good"; else die "LSP package signature check failed"; fi
    unset GNUPGHOME
  fi
  mkdir -p "$tmp/x" "$LIB/lv2"
  tar -xf "$tmp/$LSP_PKG" -C "$tmp/x" usr/lib/lv2/lsp-plugins.lv2 usr/share/licenses 2>/dev/null || tar -xf "$tmp/$LSP_PKG" -C "$tmp/x"
  rm -rf "$LIB/lv2/lsp-plugins.lv2"
  cp -r "$tmp/x/usr/lib/lv2/lsp-plugins.lv2" "$LIB/lv2/"
  mkdir -p "$LIB/licenses"; cp -r "$tmp/x/usr/share/licenses/"* "$LIB/licenses/" 2>/dev/null || true
  echo "$LSP_SHA256" > "$LIB/lsp.sha256"
fi
if ldd "$LIB/lv2/lsp-plugins.lv2/lsp-plugins-lv2.so" | grep -q 'not found'; then
  ldd "$LIB/lv2/lsp-plugins.lv2/lsp-plugins-lv2.so" | grep 'not found'
  die "LSP Plugins is missing system libraries on this SteamOS version"
fi

# ---------- 5. presets, command, PipeWire override ----------
say "Installing presets and the x20-dsp command"
mkdir -p "$DATA/presets" "$BIN" "$DROPIN_DIR"
for f in "$HERE"/presets/*.conf; do
  sed "s|@SPEAKER_SINK@|$SINK|g" "$f" > "$DATA/presets/$(basename "$f")"
done
echo "$VERSION" > "$DATA/version"
[ -f "$DATA/active" ] || echo "$PRESET" > "$DATA/active"
install -m755 "$HERE/bin/x20-dsp" "$BIN/x20-dsp"
install -m755 "$HERE/tools/measure-balance.sh" "$DATA/measure-balance.sh"
if [ -f "$UNIT_DIR/$UCM_UNIT" ]; then   # keep an earlier-added speaker profile up to date
  install -m644 "$HERE/ucm/tas2783.conf" "$DATA/tas2783.conf"
  install -m644 "$HERE/ucm/$UCM_UNIT" "$UNIT_DIR/$UCM_UNIT"
  "$BIN/x20-dsp" speaker-profile
fi

cat > "$DROPIN" <<EOF
# x20-speaker-dsp: let PipeWire find the LSP plugins installed in your home folder.
# Remove with uninstall.sh (or delete this file and run: systemctl --user daemon-reload).
[Service]
Environment="LV2_PATH=%h/.local/lib/x20-speaker-dsp/lv2:/usr/lib/lv2"
EOF
systemctl --user daemon-reload

case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not in your PATH; run $BIN/x20-dsp or add it to PATH." ;; esac

# ---------- 6. activate ----------
if [ "$ACTIVATE" = 1 ]; then
  say "Turning on preset '$PRESET' (sound cuts out for ~2 seconds)"
  "$BIN/x20-dsp" on "$PRESET"
else
  say "Installed. Turn it on with: x20-dsp on"
fi
echo
echo "Done. Commands: x20-dsp on | off | use <preset> | list | status | doctor"
