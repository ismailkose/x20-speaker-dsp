#!/usr/bin/env bash
# x20-speaker-dsp uninstaller: removes the DSP and restores stock speaker sound.
#   ./uninstall.sh         remove the DSP; keep the speaker profile so the speakers keep working
#   ./uninstall.sh --all   also remove the speaker profile install.sh may have added
#                          (on SteamOS versions without it, the speakers go silent again)
set -u
ALL=0; [ "${1:-}" = --all ] && ALL=1
DATA="$HOME/.local/share/x20-speaker-dsp"
UNIT="$HOME/.config/systemd/user/x20-speaker-ucm.service"
KEEP_PROFILE=0
[ -f "$UNIT" ] && [ "$ALL" = 0 ] && KEEP_PROFILE=1

echo "==> Removing x20-speaker-dsp"
rm -f "$HOME/.config/pipewire/pipewire.conf.d/90-x20-dsp.conf"
rm -f "$HOME/.config/systemd/user/pipewire.service.d/x20-speaker-dsp.conf"
rmdir "$HOME/.config/systemd/user/pipewire.service.d" 2>/dev/null || true
rm -rf "$HOME/.local/lib/x20-speaker-dsp"
if [ "$KEEP_PROFILE" = 1 ]; then
  # Keep only what the speaker profile needs: the command, tas2783.conf and the overlay.
  find "$DATA" -mindepth 1 -maxdepth 1 ! -name tas2783.conf ! -name LICENSE.alsa-ucm-conf ! -name ucm2 -exec rm -rf {} +
else
  if [ -f "$UNIT" ]; then
    systemctl --user disable x20-speaker-ucm.service >/dev/null 2>&1 || true
    rm -f "$UNIT" "$HOME/.config/environment.d/90-x20-speaker-ucm.conf"
    # unset-environment can't clear a value that came from environment.d, so point this
    # session back at SteamOS's own profiles; from the next login the variable is gone.
    systemctl --user set-environment ALSA_CONFIG_UCM2=/usr/share/alsa/ucm2
  fi
  rm -f "$HOME/.local/bin/x20-dsp"
  rm -rf "$DATA"
fi
systemctl --user daemon-reload
systemctl --user restart pipewire pipewire-pulse wireplumber
if [ "$KEEP_PROFILE" = 1 ]; then
  echo "Done. Speakers are back to stock sound. The X20 speaker profile was kept so they keep working"
  echo "(remove it too with: ./uninstall.sh --all)."
else
  echo "Done. Speakers are back to stock sound. (A separately installed speaker fix is untouched.)"
fi
