# Raspberry Pi 5 + LineageOS TV: fixes that make it behave like a TV box

Small, reversible fixes and findings from running **LineageOS 23.2 TV (Android 16) on a
Raspberry Pi 5** as a daily-use TV box. Everything here was found by measuring on real
hardware, and every item says what was tested and what was not.

> **Unofficial and unaffiliated.** The ROM is the community build by KonstaKANG, which comes
> from the Raspberry Vanilla device tree. The Pi 5 is not an official LineageOS device. These
> are on-device patches and write-ups, not changes to the ROM sources, and nothing here was built from
> the device tree. See [docs/UPSTREAM.md](docs/UPSTREAM.md) for what was checked upstream and why this
> is published as documentation for other users.

## Tested on

- Raspberry Pi 5 (8 GB), `lineage_rpi5_tv`, `23.2-20260520-UNOFFICIAL-KonstaKANG-rpi5_tv`
  (Android 16), booting from a USB flash drive.
- Displays: a Xiaomi Mi TV (Android 9, has CEC) and an HP monitor (no CEC). The newest
  power-sync code in `cecport` was written against an LG TV with SIMPLINK.
- The build is `userdebug`: `adb root` works and `/vendor` is plain ext4 without dm-verity
  (observed 2026-10-29). Everything that lives in `/vendor` needs that. It will not work on a
  locked-down `user` build.

## The fixes

| Fix | Problem it solves | Status |
| --- | --- | --- |
| [`cecport`](docs/hdmi-cec-and-audio-port.md): follow the TV between HDMI0 and HDMI1 | Moving the cable breaks CEC (remote dead, TV forgets the Pi) and leaves audio on the wrong port | Core tested 2026-10-29 by forcing the properties. **Not tested with a physical cable move.** |
| Same script: audio watchdog | Player freezes ("Prolonged buffering") when the audio HAL has no clock | Tested live; the give-up path only offline |
| [`cecannounce`](docs/hdmi-cec-and-audio-port.md#cecannounce-switch-the-tv-to-the-pi-after-boot) | TV stays on its own input after the Pi boots | Tested by reboot |
| [Diagnosis](docs/hdmi-cec-and-audio-port.md#remote-keys-ignored-the-pi-reports-standby): remote keys ignored | Pi's HDMI service sits in STANDBY while Android is awake | Diagnosed and fixed by hand; no automatic fix |
| [Volume](docs/volume.md): Pi far quieter than the TV's own apps | HDMI audio is treated as a speaker, so low steps are heavily attenuated (-40 dB at step 5 of 25) | Confirmed by ear on one unit |
| [Boot time](docs/boot-time.md): `loglevel=3`, no boot animation | 28 s to `boot_completed` | One boot per change; treat the numbers as indicative |
| [Network adb survives reboots](docs/system-tips.md#adb-over-the-network-after-a-reboot) | `adb` on :5555 vanishes after every reboot | Tested across a reboot |
| [Surviving a ROM update](docs/system-tips.md#surviving-a-rom-update) | Updates rewrite `/vendor` and remove the scripts | `addon.d` script only simulated |
| [Launcher swap](docs/system-tips.md#use-a-different-home-launcher) | Using a third-party launcher as Home | Verified across a reboot |

Not everything is a script: three of these are findings plus a one-line setting.

## Install the scripts

You need `adb root`. Over TCP, run `adb tcpip 5555` first, otherwise `adb root` drops the
connection and it stays offline until adb is toggled in the Pi's settings.

```sh
PI=<pi-ip>:5555
adb connect $PI
adb -s $PI tcpip 5555 && sleep 3 && adb connect $PI
adb -s $PI root && sleep 4 && adb disconnect $PI && adb connect $PI
adb -s $PI shell id -u            # must print 0

adb -s $PI shell mount -o remount,rw /vendor
for f in cecport cecannounce; do
  adb -s $PI push device/vendor/bin/$f /data/local/tmp/$f
  adb -s $PI shell "cp /data/local/tmp/$f /vendor/bin/$f && chmod 755 /vendor/bin/$f && chown root:shell /vendor/bin/$f; chcon u:object_r:initd_exec:s0 /vendor/bin/$f; rm /data/local/tmp/$f"
done
for f in cecport.rc cecannounce.rc nobootanim.rc; do   # nobootanim.rc is optional
  adb -s $PI push device/vendor/etc/init/$f /data/local/tmp/$f
  adb -s $PI shell "cp /data/local/tmp/$f /vendor/etc/init/$f && chmod 644 /vendor/etc/init/$f && chown root:root /vendor/etc/init/$f; chcon u:object_r:vendor_configs_file:s0 /vendor/etc/init/$f; rm /data/local/tmp/$f"
done
adb -s $PI shell sync
adb -s $PI shell mount -o remount,ro /vendor
```

Then reboot the Pi so init starts the services. Check with
`adb shell getprop init.svc.cecport` (`running`) and `adb shell /vendor/bin/cecport once`.

These are the same steps the author's installer used; the commands above were not re-run
verbatim as a block, so read them before pasting. Undo for each piece is in its doc.

## What was deliberately left out

Things that did not generalize or are not resolved are not published as fixes: a Wi-Fi
power-save watcher (its effect was not confirmed; `iw` still reported power save on while
Android slept), TV-specific picture settings, and anything about the author's own apps.

## Credits

ROM: [KonstaKANG](https://konstakang.com/) community builds. Device tree:
[raspberry-vanilla/android_device_brcm_rpi5](https://github.com/raspberry-vanilla/android_device_brcm_rpi5).

## License

[MIT](LICENSE) for the scripts and documentation in this repository. LineageOS, Android and the
device tree keep their own licenses; nothing from them is copied here. Use at your own risk: these
scripts run as root on `/vendor`.
