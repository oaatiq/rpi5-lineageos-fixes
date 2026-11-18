# Upstream: what was checked, and what it means for this repo

Checked on 2026-11-18 through the GitHub API and the maintainer's public replies.

## Where the Pi 5 build comes from

- **Not an official LineageOS device.** The official device list (`_data/devices` in
  `LineageOS/lineage_wiki`) has no Raspberry Pi entry. As I understand it LineageOS takes patches on
  its Gerrit instance and its GitHub repositories are mirrors, so there is no official Pi 5 tree to
  patch and a GitHub pull request to the LineageOS organization is not how a change would land.
- **The device tree is
  [`raspberry-vanilla/android_device_brcm_rpi5`](https://github.com/raspberry-vanilla/android_device_brcm_rpi5)**
  (branches `android-14.0` to `android-17.0`; the Android 16 base is `android-16.0`). It has Issues
  turned off and no license file, and its five historical pull requests were closed without merging.
- **The issue tracker is
  [`raspberry-vanilla/android_local_manifest`](https://github.com/raspberry-vanilla/android_local_manifest/issues)**,
  the only repository in that organization with Issues enabled.

## What the maintainer asks for

From his public replies on that tracker (for example
[#224](https://github.com/raspberry-vanilla/android_local_manifest/issues/224) and
[#247](https://github.com/raspberry-vanilla/android_local_manifest/issues/247)), paraphrased:

- The tracker is meant for personal builds made from the project's own source code.
- Reports need precise logs; reports with unverified or generated logs get closed.
- The project does not take feature requests. For audio the stated goal is to support a wide range of
  audio devices rather than tune for HDMI at the expense of others.
- He has no hardware to reproduce HDMI-CEC problems, and CEC depends on the TV and on adapters.
- He welcomes patches that have been built, tested and confirmed working, as pull requests, with the AI
  tools used disclosed in the commit messages.

## What that means for the findings in this repo

Being honest about fit:

- **Port following (`cecport`)** automates something the build already handles as a setting plus a
  reboot. That makes it a convenience, not a defect report.
- **HDMI volume** follows from modelling HDMI as a speaker, a choice that serves the other output
  devices too. Changing it could trade one group of users against another.
- Nothing here was built from the device tree's source, so there is no tested patch to offer. These
  are on-device workarounds.

So the most useful role of this repo is **documentation for people who hit the same symptoms**, for
example the open CEC report
[#250](https://github.com/raspberry-vanilla/android_local_manifest/issues/250), rather than a request
to the maintainer.

## If someone wants to upstream a change

Ideas only, none implemented or built. Build from source, test on hardware, then open a pull request
with AI-tool disclosure, as he asks.

| Today (this repo) | Where a patch would go |
| --- | --- |
| `cecport` follows the connected HDMI port by rewriting `persist.vendor.hdmi.cec_device` and `persist.vendor.audio.device` and restarting services | `vendor.prop` sets both to fixed defaults (`cec0`, `hdmi0`), and a code search shows `hdmi/cec/HdmiCec.cpp` and `audio/primary/StreamPrimary.cpp` reference them (file names only, the code was not read). A HAL could pick the connected connector instead. |
| `cmd media_session volume --stream 3 --set 25` | The audio policy configuration (location not checked), with care for the other output devices |
| `loglevel=3` in `cmdline.txt` | The shipped image's command line |
| `nobootanim.rc` | Skip the animation, or stop it from holding `sys.boot_completed` |
| `cecannounce` | A boot-time One Touch Play from the framework or an init service |
| `persist.adb.tcp.port=5555` | Probably should stay opt-in because of the security exposure |
