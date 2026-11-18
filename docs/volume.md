# HDMI audio is about 40 dB too quiet

Symptom: with the same TV volume, the Pi is far quieter than the TV's own apps.

## Cause

The audio HAL (vc4-hdmi cards 0 and 1) declares only `AUDIO_DEVICE_OUT_SPEAKER` in
`/vendor/etc/audio_policy_configuration.xml`, so Android treats HDMI output as a variable-volume
speaker instead of an HDMI device (which gets full-volume behaviour under CEC).

`STREAM_MUSIC` has 25 steps. Out of the box the speaker index was 5 (20 %), and the speaker curve is
`(1, -58 dB) (20, -40 dB) (60, -17 dB) (100, 0)`, so about -40 dB (about 1 % amplitude) went out of
the HDMI port. On the TV side HDMI is a fixed-volume device, so the TV knob is its only control and
cannot make up for it.

## Fix (a setting, no reboot)

```sh
cmd media_session volume --stream 3 --set 25
settings get system volume_music_speaker      # reads 25, which is 0 dB
```

Confirmed by ear on a Xiaomi Mi TV: loudness matches the TV's own apps. The value is written to
`/data/system/users/0/settings_system.xml` (checked on disk). The author did not run a dedicated
reboot test of the value 25, but the old value 5 did survive a reboot, so it is an ordinary
persisted system setting. A volume key on a remote paired to the Pi lowers it again; if it gets
quiet, read `volume_music_speaker` first.

Undo: set it back to 5. Pick a lower value if 25 (full scale) is too loud for your TV.

## Not done: the proper fix

Declaring the output as an HDMI device in the audio policy XML would give full-volume behaviour with
the TV controlling the level. It needs a reboot and is lost on a ROM update, and it was not tried. It
belongs in the device tree (see [UPSTREAM.md](UPSTREAM.md)).
