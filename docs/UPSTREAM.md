# Getting these fixes upstream

Most of what is here is a workaround running on a finished image. The right long-term home for each
item is the device tree, where it would not need root, a remount, or a watcher script. Where that
tree lives matters, so here is what was checked on 2026-11-18.

## Where the Pi 5 build comes from

- **Not an official LineageOS device.** The official device list (`_data/devices` in
  `LineageOS/lineage_wiki`) has no Raspberry Pi entry. As I understand it LineageOS takes patches on
  its Gerrit instance and its GitHub repositories are mirrors, so a GitHub pull request to the
  LineageOS organization is not how a change lands, and there is no official Pi 5 tree to patch.
- **The device tree is `raspberry-vanilla/android_device_brcm_rpi5`.** Branches `android-14.0`
  through `android-17.0` (default `android-17.0`); the Android 16 base is `android-16.0`. The
  repository has Issues turned off, no license file, and its five historical pull requests were all
  closed without being merged. Contact with the maintainer is therefore likely outside GitHub
  (KonstaKANG's own project pages); check there for the current channel before sending anything.

## What a proper fix would look like

These are proposals. None has been built against the device tree.

| Today (this repo) | Proper home |
| --- | --- |
| `cecport` follows the connected HDMI port by rewriting `persist.vendor.hdmi.cec_device` and `persist.vendor.audio.device` and restarting services | `vendor.prop` sets both to fixed defaults (`cec0`, `hdmi0`), and a code search shows `hdmi/cec/HdmiCec.cpp` and `audio/primary/StreamPrimary.cpp` reference them (only the file names were checked, not the code). The HALs could pick the connector that is connected instead of a static value. `cecport`'s logic is the spec. |
| `cmd media_session volume --stream 3 --set 25` | Declare the HDMI output as an HDMI device in the audio policy configuration so Android uses full-volume behaviour (not located or tried) |
| `loglevel=3` in `cmdline.txt` | The shipped image's command line |
| `nobootanim.rc` | Skip the animation, or stop it from holding `sys.boot_completed` |
| `cecannounce` | A boot-time One Touch Play from the framework or an init service in the tree |
| `persist.adb.tcp.port=5555` | Probably should stay opt-in because of the security exposure |

## Suggested way to approach it

1. Publish this repo (done first, so the findings are searchable and citable).
2. Open a short, specific request to the maintainer rather than a large pull request: one
   problem, the symptom, the measured cause, and the smallest change. The strongest candidates
   are the audio-port/CEC-port-follows-connector bug (reproducible by moving the cable) and the
   `-40 dB` HDMI volume curve.
3. Offer the evidence in this repo: the `n=0 err=...` audio clock symptom, the NullPointerException
   that results from restarting only the CEC HAL, and the numbers in
   [boot-time.md](boot-time.md).
