# HDMI-CEC and the HDMI audio port

The Pi 5 has two HDMI outputs and two CEC adapters:

| Port | DRM connector | CEC node | Audio value |
| --- | --- | --- | --- |
| HDMI0 (micro-HDMI next to USB-C power) | `HDMI-A-1` | `cec0` | `hdmi0` |
| HDMI1 | `HDMI-A-2` | `cec1` | `hdmi1` |

Two properties pin Android to one port, and the stock defaults are `cec0` and `hdmi0`:

- `persist.vendor.hdmi.cec_device` is read by the CEC HAL when it starts.
- `persist.vendor.audio.device` is read by the audio HAL when it (re)starts.

If your TV is on the other port, things break in ways that do not point at the cause.

By design, according to the maintainer's reply in
[issue #224](https://github.com/raspberry-vanilla/android_local_manifest/issues/224), the port is
chosen in the ROM's Raspberry Pi settings (HDMI0 by default) and the device must be rebooted after
changing it. The watcher below only automates following the cable; it is a convenience the stock
build does not claim to offer.

## Remote keys ignored: the Pi reports STANDBY

Symptom: the TV remote does nothing on the Pi although the CEC wire is fine.

`dumpsys hdmi_control | grep mPowerStatus` shows `mPowerStatus: 1` (STANDBY) while Android is
awake. No sleep-to-wake transition ever flipped it to ON, so the Pi answers the TV's power poll
with `<Report Power Status> 0x01`, the TV lists it as `CONNECTED_STANDBY`, and a standby HDMI
service drops every `<User Control Pressed>` except the power keys. It also never sent
`<Active Source>`.

Fix by hand: one sleep/wake cycle makes `mPowerStatus` go to 0. If `power_control_mode` is
`broadcast`, sleeping the Pi sends `<Standby>` and turns the TV off, so set it to `none` first
(`cmd hdmi_control cec_setting set power_control_mode none`) and restore it afterwards.
There is no automatic fix; one boot after this was diagnosed came up clean without it.

On Android 16 the old `Settings.Global` CEC keys read null. Use
`cmd hdmi_control cec_setting get|set <name>`.

## Remote keys ignored: wrong CEC adapter

If the TV is on HDMI1 but `persist.vendor.hdmi.cec_device` is `cec0`, every send fails with
"Machine is not on the network" and the TV drops the Pi from its device list. Check which port
is live with `cat /sys/class/drm/card*-HDMI-A-1/status /sys/class/drm/card*-HDMI-A-2/status`.

A monitor has no CEC: messages addressed to the TV (logical address 0) all FAIL, broadcasts are
ACKed and `mIsCecAvailable` is false. That is normal, not a fault. Identify the display from
`/sys/class/drm/card*-HDMI-A-N/edid` (manufacturer bytes 8-9).

## Player freezes after moving the cable: wrong audio port

With `persist.vendor.audio.device` naming a port with nothing connected, the audio output has no
clock: `dumpsys media.audio_flinger` shows `Timestamp stats: n=0 ... err=<large>` and
`Frames written: 0`. A player that slaves its media clock to audio then races about 7x real
time, drops frames in batches and sits in BUFFERING: 1 s of picture, 3 to 8 s frozen, repeating.
It is not the network, decoder, CPU or refresh rate. `n=0` with a growing `err` is the tell.

Fix by hand (no reboot, apps recover by themselves):

```sh
setprop persist.vendor.audio.device hdmi0      # or hdmi1
stop audioserver; stop vendor.audio-rpi; stop vendor.audio-effect-rpi; sleep 1
start vendor.audio-effect-rpi; start vendor.audio-rpi; sleep 2; start audioserver
```

## `cecport`: do it automatically

`device/vendor/bin/cecport` is an init service (`cecport.rc`, started at `sys.boot_completed=1`).
Every 5 s it reads the two connector `status` files. When exactly one port is connected and has
stayed that way for 3 polls (about 15 s):

- **Audio**: if the audio property names the other port, set it and restart the three audio
  services. No reboot. It then checks the result and logs `audio clock is working (n=..)`,
  `audio still not keeping time`, or `nothing playing to check`.
- **CEC**: if the CEC property names the other port, do a *soft switch*: set both properties,
  `stop zygote`, restart `vendor.cec-rpi`, `vendor.hdmi-rpi` and the audio services while
  nothing polls them, `start zygote`, then wait up to 90 s for `hdmi_control` and confirm the
  CEC HAL has `/dev/cecN` open. About 12 s instead of about 80 s for a reboot (apps are closed
  either way). If that does not check out it falls back to a reboot (`reboot,cec-port`).
- It does nothing when neither or both ports are connected, tries once per port (guard property
  `persist.vendor.cec_port.guard`), and leaves any `audio.device` value other than `hdmi0` or
  `hdmi1` alone.
- **Audio watchdog**: every 15 s, if no output thread has a working clock (`n=0`) and `err` grew
  by 50 or more since the last look, restart the audio services. At most 3 in a row, 60 s apart,
  then it stays quiet until the clock works or errors stop growing. Idle (`n=0`, flat errors)
  and healthy playback are never touched. Constants are at the top of the script.

It logs to logcat (tag `cec-port`) and to `/data/local/tmp/cecport.log` (capped at 100 KB), because
the framework restart rotates the small logcat buffer. `cecport once` prints what it sees without
changing anything.

### Traps found the hard way

- **Never restart only the CEC HAL while the framework runs.** `HdmiControlService` keeps polling
  the dead HAL, throws a `NullPointerException` in `HdmiCecController.nativeSendCecCommand`,
  `system_server` dies and the whole framework restarts. The soft switch stops the framework
  first. The audio HAL, in contrast, can be restarted on its own.
- **Bare `dumpsys` hangs in an init service.** Its shell has `/vendor/bin` first in PATH and
  `/vendor/bin/dumpsys` talks to the vendor binder, where `media.audio_flinger` does not exist.
  The script calls `/system/bin/dumpsys` under `timeout 5`. Stub-based tests cannot catch this.
- `service check` prints "not found", which a naive `grep found` matches. The script greps
  `Service hdmi_control: found`.
- `stop cecport` does not stay stopped across a framework restart, because `sys.boot_completed`
  fires `start cecport` again. To pause it, `kill -STOP` its shell and `kill -CONT` later.
- Init services' `log` lines often do not show up in logcat on this ROM, hence the log file.

### Status of each part

Tested 2026-10-29 on a monitor on HDMI0 by forcing the properties to `cec1`/`hdmi1`: `cecport`
decided by itself, logged the soft switch, the framework was back in about 12 s with no reboot, and
video playback had a healthy audio clock afterwards. The HAL following the property to the
other adapter was shown separately by hand. The audio watchdog was cured live in about 27 s with the
clock deliberately stuck. A bug in the first watchdog version (a baseline reading reset the retry
counter, so it could restart forever) was caught offline and fixed.

**Not tested:** a physical cable move; a real TV answering after a soft switch; the watchdog's
give-up path on a real Pi.

### Later additions (less tested)

The version in this repo is the one running on the author's unit since 2026-11-14. It adds, on top
of everything above, code written in later sessions and **reviewed here by reading only**:

- `check_cec_available`: if the port already matches but `mIsCecAvailable` stays false, run the
  soft switch once per stuck episode.
- `announce_if_needed`: send One Touch Play each time a port goes from disconnected to connected,
  not just at boot.
- A power-sync block written for an LG TV with SIMPLINK and Quick Start+ off: it holds a kernel
  wake lock (`cec_no_suspend`) so Android can sleep without the Pi suspending off the network, sets
  `persist.sys.hdmi.keep_awake=false` so a TV `<Standby>` can put Android to sleep, and wakes
  Android when the TV powers back on. It calls `cec-ctl`, which ships with the ROM. **This block
  changes sleep behaviour.** If you do not want it, delete the "Power sync" section and the
  `wake_if_tv_*` calls, and run `setprop persist.sys.hdmi.keep_awake ""` and reboot to undo the
  property.

### Fix: "Ethernet not connected" after a soft switch (2026-11-20)

Seen on the author's unit: 14 s after Android went to sleep, `check_cec_available` found CEC
unavailable and ran the soft switch. Afterwards the Pi showed "Ethernet not connected" with the
cable in. The link was up at 1000 Mb/s and DHCP had given an address, but the `eth0` routing table
was empty, so no traffic passed and Android never marked the network as validated. Only a reboot
cleared it.

Cause: when the framework crashes, init restarts `netd`, `wificond`, `cameraserver` and `media`
with it (the `onrestart` lines of `init.zygote64.rc`). A `stop zygote` / `start zygote` skips
them. `netd` kept the old framework's networks, and the new framework's Ethernet network got the
same network id and no routes.

The script now does two things differently:

- `soft_switch` stops and starts `netd`, `wificond`, `cameraserver` and `media` while the
  framework is down, as init does.
- `check_cec_available` only counts while Android is awake. While Android sleeps, an unavailable
  CEC is normal and no reason to restart anything.

Tested on the author's unit: a later soft switch (Pi woken while the TV stayed off) restarted
`netd` with the framework, and Ethernet kept its routes and its validated state. The LG remote
still puts the Pi to sleep and wakes it.

`AVAIL_STABLE` is now 60 polls (5 minutes) instead of 6 (30 s). CEC is also unavailable while the
Pi is awake and the TV is off or still starting, and at 30 s that alone restarted the framework
(seen when the Pi was woken while the TV stayed off). A CEC that is really stuck is now repaired
after 5 minutes instead of 30 s.

Before that, `check_cec_available` now tries a lighter repair: after `AVAIL_TOGGLE` polls (20 s)
of an unavailable CEC while Android is awake, it turns HDMI-CEC off and on inside Android
(`cmd hdmi_control cec_setting set hdmi_cec_enabled 0`, then `1`). Tested on the author's unit with
the Pi woken while the TV was off: the TV turned on, CEC stayed unavailable, and after the toggle it
was available again in about 7 s. Android was not restarted, Ethernet was untouched, and the Pi
announced itself as the active source again. The framework restart stays as the fallback at
5 minutes.

## cecannounce: switch the TV to the Pi after boot

With `routing_control` on (`cmd hdmi_control cec_setting set routing_control 1`) the Pi switches
the TV to its input when it wakes from sleep, but not when it boots. `cecannounce` waits 25 s after
`sys.boot_completed` and runs `cmd hdmi_control onetouchplay`, which sends `<Text View On>` and
`<Active Source>`. On the Android 9 Xiaomi TV used for testing, the matching TV-side setting was
`settings put global hdmi_control_auto_wakeup_enabled 1`; other TVs have their own switch.

Tested by reboot 2026-10-29: the Pi announced about 25 s after boot completed and the TV registered
it as the active source.

**Changed 2026-11-20: ask early, retry, confirm.** Waiting a fixed 25 s and asking once was slow
and could miss a TV that was still starting up. `cecannounce` now asks as soon as
`HdmiControlService` is up, reads the TV's CEC power status every 3 s, asks again while the TV is
not on (for up to 60 s), and once the TV reports on asks one last time so it switches to the Pi's
input. It stops if Android goes back to sleep. Each step goes to `/data/local/tmp/cecannounce.log`,
readable over adb.

Measured on the author's unit (LG TV, off before the reboot):

| Since kernel start | Before | After |
|---|---|---|
| Android ready | 35 s | 19 s |
| First request to the TV | 61 s | 21 s |
| TV reports on | 73 s | ~35 s (third request; the first two went out while it was starting up) |

Android's boot time varied between the two runs, so compare the gap from "Android ready" to "TV
on": 38 s before, about 15 s after, most of it the TV's own start-up.

It must be an **init `.rc` service, not an `init.d` script that backgrounds itself**: `sysinit` is a
oneshot service and Android 16's init kills its process group when it exits, so a detached child
never survives. The first attempt as `/vendor/etc/init.d/` ran fine by hand and never fired at boot.

## Remote cannot wake a halted Pi

A Pi shut down with `svc power shutdown` stayed off in the author's test: the Xiaomi remote's
power-on did not boot it, and it needed the Pi's own power button or a power cycle. Only Android
sleep and wake work through the remote. The "asleep" Pi is software sleep only:
the ROM runs `vendor.suspend_blocker-rpi`, so `/sys/power/suspend_stats` shows 0 suspends and
the CPUs stay online.

## Undo

```sh
adb root; adb shell "mount -o remount,rw /vendor; rm /vendor/bin/cecport /vendor/etc/init/cecport.rc /vendor/bin/cecannounce /vendor/etc/init/cecannounce.rc; sync; mount -o remount,ro /vendor"
adb shell setprop persist.sys.hdmi.keep_awake ""     # only if you ran the power-sync version
adb reboot
```
