#!/usr/bin/env bash
# x20-speaker-dsp uninstaller: removes everything install.sh added and restores stock speaker sound.
set -u
echo "==> Removing x20-speaker-dsp"
rm -f "$HOME/.config/pipewire/pipewire.conf.d/90-x20-dsp.conf"
rm -f "$HOME/.config/systemd/user/pipewire.service.d/x20-speaker-dsp.conf"
rmdir "$HOME/.config/systemd/user/pipewire.service.d" 2>/dev/null || true
rm -f "$HOME/.local/bin/x20-dsp"
rm -rf "$HOME/.local/share/x20-speaker-dsp" "$HOME/.local/lib/x20-speaker-dsp"
systemctl --user daemon-reload
systemctl --user restart pipewire pipewire-pulse wireplumber
echo "Done. Speakers are back to stock sound. (Your speaker fix, if installed, is untouched.)"
