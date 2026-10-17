# Useful Commands

## i3 idle locking

Move the mouse or press a key when the screen-lock warning appears to restart the idle timer.
The warning also appears over fullscreen windows and while notifications are paused.
Use the mouse or a modifier key such as Shift to avoid typing into the focused application.
The warning is transient, so it expires even while the session stays idle.

The warning and idle locker are configured in [i3 session services](../../modules/apps/i3wm/services.nix).

## General CLI

### less

Open a file and immediately scroll to the bottom (end of file):

```bash
fp="file.txt"
less +G $fp
```

### sponge (moreutils)

Read standard input and write it to a file, soaking up all input before opening the output file (useful for reading from and writing to the same file in a pipeline).
If no file is specified, it writes to standard output:

```bash
fp="file.txt"
cat $fp | sort | sponge $fp

```
