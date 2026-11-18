# System tips

## adb over the network after a reboot

The ROM's "Network debugging" toggle only sets `service.adb.tcp.port` at runtime, so `adb connect
<pi-ip>:5555` stops working after every reboot until someone toggles it in Settings.

```sh
adb shell setprop persist.adb.tcp.port 5555
```

adbd falls back to `persist.adb.tcp.port` when `service.adb.tcp.port` is empty. After setting it,
adb came back on its own after a reboot, and the property was still set weeks later. It lives in
`/data`, so it survives a ROM update but not a wipe or re-flash.

Persistent network adb is a real exposure on a shared network. Use it on a LAN you trust.

### Getting root over TCP

This is a `userdebug` build, so `adb root` works, but over TCP it kills the listener and adb stays
"offline" until it is toggled in Settings. This sequence avoids that (no reboot needed):

```sh
adb connect <pi-ip>:5555
adb -s <pi-ip>:5555 tcpip 5555      # first
adb -s <pi-ip>:5555 root
adb disconnect <pi-ip>:5555; adb connect <pi-ip>:5555
adb -s <pi-ip>:5555 shell id -u     # 0
```

A reboot returns adbd to uid 2000 (shell). `su` does not exist. `/vendor` is plain ext4 with no
dm-verity: `mount -o remount,rw /vendor` works as root. `chcon --reference` is unsupported, so pass
the label explicitly (`u:object_r:initd_exec:s0` for scripts, `u:object_r:vendor_configs_file:s0`
for `.rc` files).

The Pi has no RTC: until NTP syncs, timestamps read the ROM's build date, so old-looking entries in
`dumpsys` can be from the current boot.

## Surviving a ROM update

The ROM is non-A/B and is updated with the LineageOS Updater plus recovery, which rewrites `/system`
and `/vendor`. That removes everything installed under `/vendor`.

`addon.d/60-cec.sh` is an `addon.d` survival script (the same mechanism `30-gapps.sh` uses): during an
update the updater runs it to back up and restore `cecport`, `cecport.rc`, `cecannounce` and
`cecannounce.rc`. **It has only been simulated with stub functions; no real update has been run with
it installed.** It does not cover `nobootanim.rc` or `/boot/cmdline.txt`. Install it with:

```sh
adb root; adb shell mount -o remount,rw /
adb push addon.d/60-cec.sh /data/local/tmp/60-cec.sh
adb shell "cp /data/local/tmp/60-cec.sh /system/addon.d/60-cec.sh && chmod 755 /system/addon.d/60-cec.sh && chown root:root /system/addon.d/60-cec.sh; chcon u:object_r:system_file:s0 /system/addon.d/60-cec.sh; rm /data/local/tmp/60-cec.sh"
adb shell mount -o remount,ro /
```

Whatever the update method, after every update verify rather than assume: compare the installed
files with this repo (`adb shell sha256sum /vendor/bin/cecport ...`), check `loglevel=3` is still in
`/boot/cmdline.txt` and `getprop persist.adb.tcp.port` still reads `5555`. If the files are missing
nothing breaks: the Pi still works, it just stops following the TV's HDMI port and stops switching
the TV to itself at boot.

## Use a different Home launcher

Before the change, a third-party launcher (HOME intent-filter priority 0) did not come up as the
default after reboots: the stock `com.google.android.tvlauncher` held the HOME role and was the only
preferred HOME activity (priority 2).

```sh
adb shell cmd role add-role-holder --user 0 android.app.role.HOME <your.launcher.package>
adb shell pm disable-user --user 0 com.google.android.tvlauncher
```

Disabled, not uninstalled: `/system/product` is read-only, and a disable lives in `/data` so it
survives ROM updates. Verified across a reboot: the role holder and the disabled state persisted and
the third-party launcher was focused with no key pressed. Leave
`com.android.tv.settings/.system.FallbackHome` (priority -1000, the system fallback) alone.

Undo:

```sh
adb shell pm enable com.google.android.tvlauncher
adb shell cmd role add-role-holder --user 0 android.app.role.HOME com.google.android.tvlauncher
```

If the launcher is still wrong after a reboot, check `dumpsys role | grep -A3 role.HOME` and
`pm list packages -d`.
