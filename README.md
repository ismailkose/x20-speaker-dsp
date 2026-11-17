# x20-speaker-dsp

Better built-in speaker sound for the **ASUS ROG Xbox Ally X20 (RC74XA)** on **SteamOS**.

A PipeWire filter chain tuned for the X20's two speakers: wider stereo, steadier loudness, and protection against harsh peaks and distortion. One command installs it, everything lives in your home folder (no sudo), and it survives SteamOS updates.

**Speakers silent after a fresh SteamOS install?** The installer fixes that too on SteamOS 3.10+. No sudo, no reboot.

> **X20 only.** The 2025 ROG Xbox Ally X (RC73XA) uses different audio hardware (Realtek ALC294 + TI TAS2781 over I2C). The X20 uses a Realtek rt721 codec + 2× TI TAS2783 amps over SoundWire. The installer checks this and refuses to run on other devices.

---

## Requirements

- ROG Xbox Ally X20 (RC74XA) running SteamOS 3.9+ (tested on 3.10.1: PipeWire 1.6.8, WirePlumber 0.5.18)
- Nothing else. If the speakers are silent (fresh SteamOS shows only HDMI or "Dummy Output"), the installer adds the missing speaker profile itself. See [Silent speakers](#silent-speakers-on-a-fresh-steamos).
- Internet connection during install (to download LSP Plugins from the Arch Linux archive)

## Install

In **Desktop Mode**, open **Konsole** and run:

```bash
git clone https://github.com/ismailkose/x20-speaker-dsp.git
cd x20-speaker-dsp
./install.sh
```

Sound cuts out for about 2 seconds while PipeWire restarts. That's it. The DSP lives in PipeWire, so it applies in Game Mode as well (tuned and tested in Desktop Mode).

## Silent speakers on a fresh SteamOS

On SteamOS 3.10 (kernel 7.3) the kernel and TI amp firmware already support the X20 speakers. The one missing piece is the ALSA speaker profile (`sof-soundwire/tas2783.conf`). It's already in upstream [alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf) but not yet in SteamOS. Without it PipeWire can't open the sound card, so only HDMI or "Dummy Output" shows up.

If the speakers are silent, `install.sh` checks that the kernel driver is up (the card reports `spk:tas2783`) and then adds the profile in your home folder:

- `~/.local/share/x20-speaker-dsp/ucm2/`: links to all of SteamOS's own ALSA profiles plus `tas2783.conf`
- `~/.config/environment.d/90-x20-speaker-ucm.conf`: points PipeWire at it
- `x20-speaker-ucm.service`: rebuilds the links at every login, so SteamOS updates to its profiles still apply. Once SteamOS ships `tas2783.conf` itself, the bundled copy is no longer used

Older SteamOS versions (3.9, kernel 7.2) lack the kernel support too. There the installer stops and points you to the full fix, which needs sudo and a reboot: [hungarianhc/rog-ally-x20-steamos-speakers](https://github.com/hungarianhc/rog-ally-x20-steamos-speakers). Use `./install.sh --no-speaker-fix` to skip this step.

## Usage

```bash
x20-dsp status          # is it on?
x20-dsp off             # stock speaker sound
x20-dsp on              # back on (last used preset)
x20-dsp list            # available presets
x20-dsp use wide        # switch preset
x20-dsp doctor          # check the installation if something seems wrong
```

Only the **built-in speakers** are processed. Headphones, HDMI, Bluetooth and USB audio bypass the DSP automatically, and you keep one normal volume control.

### Presets

| Preset | Widening | Leveler | Use it if… |
|---|---|---|---|
| **`xtc`** (default) | crosstalk cancellation | gentle | you want the best all-round sound |
| `wide` | mid/side, 0.8 | gentle | you prefer a simpler "bigger" stereo |
| `xtc-no-leveler` | crosstalk cancellation | off | you want untouched dynamics (music listening) |

All presets share the same fast compressor and limiters.

## What it does

```
apps ─► widening ─► leveler ─► fast compressor ─► per-band limiter ─► limiter ─► speakers
```

| Stage | Settings | Why |
|---|---|---|
| Speaker amps | X20 TI TAS2783 firmware (loaded by the kernel) | the hardware's own speaker tuning — nothing to add on top; the X20's speaker EQ is flat |
| **Crosstalk-cancel widening** (`xtc`) | side signal only, 250 Hz–6 kHz, 75 µs delay, gain 0.55 (+0.30 second order) | each speaker sends an inverted, delayed copy of the other side to cancel the sound that leaks to the wrong ear, so the stage sounds wider than the device. The 75 µs comes from the X20's speaker geometry (~10° spread). Center content (voices, dialogue) is untouched |
| Mid/side widening (`wide`) | side +5 dB above 300 Hz | simpler alternative; bass stays centered |
| **Leveler** | target −20 LUFS, ±12 dB tolerance, max +12 dB boost, slow (8–10 s) | evens out very quiet vs very loud content without "pumping" normal material |
| **Fast compressor** | −14 dB threshold, 3:1, 6 dB soft knee, 3 ms attack, 120 ms release, 2 ms lookahead, RMS, stereo-linked | catches sudden peaks (gunshots after dialogue) while keeping punch |
| Per-band limiter | 8 bands (splits at 81, 182, 277, 392, 555, 933, 1164 Hz), +4 dB input gain, values derived from ASUS's X20 tuning | protects the small drivers band by band |
| Limiter | final safety ceiling | no clipping |

There's deliberately **no bass enhancer**: on these speakers it made bass buzz at higher volume.

CPU use is about 1% of one core.

### Measured

Measured with `tools/measure-balance.sh` (post-DSP, digital):

| | Left | Right |
|---|---|---|
| left-only input | −19.1 dB | −34.8 dB |
| right-only input | −34.8 dB | −19.1 dB |
| both channels | −21.3 dB | −21.3 dB |

Perfectly symmetric (0.0 dB balance), with ~16 dB of crosstalk cancellation on the opposite channel. Note the leveler needs a few seconds to settle after silence, so the very first sound in a test video can seem quieter.

Run it yourself (DSP on, volume low):

```bash
~/.local/share/x20-speaker-dsp/measure-balance.sh
```

## Uninstall

```bash
cd x20-speaker-dsp
./uninstall.sh
```

Removes the DSP. If the installer added the speaker profile, it's kept so your speakers keep working. Use `./uninstall.sh --all` to remove that too. A separately installed speaker fix is never touched.

## Troubleshooting

- **`x20-dsp status` says the filter is not loaded**, e.g. after a SteamOS update: run `x20-dsp doctor`. Sound keeps working without the DSP in the meantime. Re-running `./install.sh` fixes most issues.
- **No speaker sound at all:** run `x20-dsp doctor`. If "speaker driver loaded" fails, your SteamOS needs the [full speaker fix](https://github.com/hungarianhc/rog-ally-x20-steamos-speakers). If only "speaker profile" or "speaker sink" fails, re-run `./install.sh`.
- **Audio processed twice / sounds odd:** quit EasyEffects and remove other speaker DSPs (for example ones made for the 2025 Ally X). `x20-dsp doctor` warns about EasyEffects.
- **Widening sounds "phasey":** hold the device centered in front of you; crosstalk cancellation works best from the middle. Or try `x20-dsp use wide`.

## Files installed

| Path | What |
|---|---|
| `~/.local/bin/x20-dsp` | the command |
| `~/.local/share/x20-speaker-dsp/` | presets, state, measurement tool |
| `~/.local/lib/x20-speaker-dsp/lv2/` | LSP Plugins (downloaded, checksum + Arch signature verified) |
| `~/.config/pipewire/pipewire.conf.d/90-x20-dsp.conf` | the active preset (absent when off) |
| `~/.config/systemd/user/pipewire.service.d/x20-speaker-dsp.conf` | tells PipeWire where the plugins are |
| `~/.config/environment.d/90-x20-speaker-ucm.conf`, `~/.config/systemd/user/x20-speaker-ucm.service` | speaker profile, only if your speakers were silent |

## Credits & license

- Scripts and presets: MIT, see [LICENSE](LICENSE).
- [speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects) (MIT) by Antoine Cellerier, used to build the initial chain.
- [LSP Plugins](https://lsp-plug.in/) (LGPL-3.0), downloaded at install time and not included in this repo.
- `ucm/tas2783.conf` is an unmodified copy from [alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf) (BSD-3-Clause, see `ucm/LICENSE.alsa-ucm-conf`).
- [hungarianhc/rog-ally-x20-steamos-speakers](https://github.com/hungarianhc/rog-ally-x20-steamos-speakers) for working out how to get the X20 speakers running on SteamOS.

See [NOTICE.md](NOTICE.md) for where the values come from. Not affiliated with ASUS, Microsoft or Valve.
