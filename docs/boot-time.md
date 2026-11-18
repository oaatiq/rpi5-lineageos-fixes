# Boot time: 28 s to `boot_completed`, and what moved it

All times are kernel-clock seconds from a single boot per configuration, so expect a few seconds of
boot-to-boot noise. Read them with `adb shell getprop | grep boottime` and
`adb shell logcat -b events -d | grep boot_progress`. `ro.boottime.cecport` is the moment
`sys.boot_completed` fires (the instant `cecport` starts).

Baseline (two boots): init 4.1, `ueventd` 9.1, zygote 12.9, `boot_progress_start` 15.6-15.9,
`enable_screen` 22.7-22.8, `boot_completed` 28.1-28.3.

## 1. Serial console at loglevel 7 (`loglevel=3`)

The kernel console is the 115200-baud debug UART (`console=ttyAMA10,115200`) at console loglevel 7,
and a `printk` blocks until it is written out. Measured on the Pi: 200 log lines took 2072 ms at
loglevel 7 and 11 ms at loglevel 1 (about 10 ms per line). A boot prints about 900 lines (about
85 KB, 7.4 s of UART time) before `boot_completed`.

Change: append ` loglevel=3` to `cmdline.txt` on the FAT boot partition (mounted at `/boot`; it was
`/dev/block/sda1` on a USB-boot unit). `dmesg` still keeps everything; only the serial echo is cut.

```sh
cp /boot/cmdline.txt /data/local/tmp/cmdline.txt.orig       # back up first
mount -o remount,rw /boot
# append " loglevel=3" to the single line in /boot/cmdline.txt, with no newline in the middle
sync; mount -o remount,ro /boot
```

Result: `boot_completed` at 23.3 s on one boot (about 5 s saved).
Undo: remove ` loglevel=3`. If the Pi will not boot, plug the boot drive into a PC and edit
`cmdline.txt` on the first (FAT) partition. A ROM update may overwrite this partition.

## 2. Boot animation off

`/product/media/bootanimation.zip` has three parts (1.0 s once, 1.5 s looping, 3.5 s ending), all
play-until-complete. When Android finishes booting the animation still plays out its loop and the
ending (about 4-5 s) and `sys.boot_completed` and the launcher wait for it. That is the gap between
`enable_screen` (22.7 s) and `boot_completed` (28.2 s) in the baseline.

Change: `device/vendor/etc/init/nobootanim.rc` installed as `/vendor/etc/init/nobootanim.rc`:

```
on early-init
    setprop debug.sf.nobootanimation 1
```

`/system/bin/bootanimation` honors that property: it logs "boot animation disabled" and exits, and
the `bootanim` service no longer starts (`getprop init.svc.bootanim` is empty).

Result on one boot (with `loglevel=3` already in place): `enable_screen` 17.9 s, `boot_completed`
18.35 s. A later boot on the same unit read 21.1 s, so treat "about 18-21 s" as the honest range.
The screen is black from HDMI sync until the launcher appears.

Undo: remount `/vendor` rw, delete the `.rc`, remount ro, reboot.

## Checked and not worth changing

- The boot drive reads 310 MB/s sequentially; `read_ahead_kb` of 128, 1024 and 4096 made no
  difference.
- The disk was busy 32 s of the first 80 s (1.28 GB read, mostly small reads from `/system`), so
  storage latency is the next limit. The boot disk was a USB flash drive on plain `usb-storage`
  (not UAS). One 32 s read stall with a USB reset and an I/O error on the data partition appeared in
  one of three boots.
- An SSD (USB, or PCIe NVMe via the `android-nvme` overlay already present in `config.txt`) is the
  largest remaining win. Small fsync'd writes on the flash drive averaged 24 ms (worst 43 ms).

Untested ideas: disable the camera and GNSS HALs; prefetch the boot working set.
