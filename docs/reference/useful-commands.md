# Useful Commands

## i3 idle locking

Move the mouse or press a key while the idle screensaver is showing to return to the desktop without a password.
The screensaver uses the lock screen's theme and clock, and dismissing it restarts the idle timer.
Continued inactivity starts the authenticated lock screen.
Manual locking and locking for suspend require authentication immediately.

The screensaver and idle locker are configured in [i3 session services](../../modules/apps/i3wm/services.nix).

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
