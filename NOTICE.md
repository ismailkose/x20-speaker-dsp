# Notice: where the values come from

## Derived from ASUS's X20 tuning

The **per-band limiter** stage (`reg`, an LSP multiband compressor) and its **+4 dB input gain** use parameter values converted from the speaker tuning that ASUS ships for the ROG Xbox Ally X20 (RC74XA) in its Windows audio driver package:

- Package: ASUS audio driver for RC74XA, version V11.605.945.20 (from ASUS's support site)
- Tuning file: `SOUNDWIRE_SDCAFUNCTION_10_MAN_0102_FUNC_0000_SUBSYS_19541043.xml`, Game profile
- Conversion: [speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects) (MIT)

Only numeric parameters appear in this repository. No ASUS files are included.

Facts read from the same file, used as design inputs and not copied as code:
- The X20's speaker correction EQ is flat, so this package applies none.
- Leveler target loudness: −20 LUFS.
- Speaker spread of 10 is the basis for the 75 µs crosstalk-cancellation delay.

## Designed for this package

These were designed for the X20 and tuned by listening tests on the device:
- the crosstalk-cancellation and mid/side widening stages
- the gentle leveler settings (tolerance, boost cap, timing)
- the fast compressor

## Third-party software

- **LSP Plugins** 1.2.37 (LGPL-3.0). `install.sh` downloads it from the official Arch Linux archive and checks its SHA-256 and the Arch packager signature. It is not redistributed in this repository.
- **speaker-tuning-to-easyeffects** (MIT, © 2026 Antoine Cellerier). Its code is not included; only configuration it helped generate is.

All trademarks belong to their owners. This project is not affiliated with ASUS, Microsoft, Valve or Dolby.
