## systemd

### `machine-id(5)`

`systemd` uses per-machine identifier — [machine-id(5)](https://www.freedesktop.org/software/systemd/man/machine-id.html) — which must be unique and persistent; otherwise, the system journal may fail to list earlier boots, etc.

`systemd` generates a random `machine-id(5)` during boot if it does not already exist, and persists it in `/etc/machine-id`. As such, it suffices to make that file persistent.

Alternatively, it is possible to generate a random `machine-id(5)`; while the specification allows for _any_ hex-encoded 128b value, systemd itself uses [UUIDv4](<https://en.wikipedia.org/wiki/Universally_unique_identifier#Version_4_(random)>), _i.e._ random UUIDs, and it is thus preferable to do so as well, in case some software assumes `machine-id(5)` to be a UUIDv4. Those can be generated with `uuidgen -r | tr -d -` (`tr` being used to remove the dashes).

Such a `machine-id(5)` can be set by writing it to `/etc/machine-id` or through the kernel’s command-line, though NixOS’ systemd maintainers [discourage](https://github.com/NixOS/nixpkgs/pull/268995) the latter approach.

### `/var/lib/systemd`

Moreover, `systemd` expects its state directory — `/var/lib/systemd` — to persist, for:

- [systemd-random-seed(8)](https://www.freedesktop.org/software/systemd/man/systemd-random-seed.html), which loads a 256b “seed” into the kernel’s RNG at boot time, and saves a fresh one during shutdown;

- [systemd.timer(5)](https://www.freedesktop.org/software/systemd/man/systemd.timer.html) with `Persistent=yes`, which are then run after boot if the timer would have triggered during the time the system was shut down;

- [systemd-coredump(8)](https://www.freedesktop.org/software/systemd/man/systemd-coredump.html) to store core dumps there by default; (see [coredump.conf(5)](https://www.freedesktop.org/software/systemd/man/coredump.conf.html))

- [systemd-timesyncd(8)](https://www.freedesktop.org/software/systemd/man/systemd-timesyncd.html);

- [systemd-backlight(8)](https://www.freedesktop.org/software/systemd/man/systemd-backlight.html) and [systemd-rfkill(8)](https://www.freedesktop.org/software/systemd/man/systemd-rfkill.html) persist hardware-related state;

- possibly other things, this list is not meant to be exhaustive.

In any case, making `/var/lib/systemd` persistent is recommended.

### `/var/log/journal/`

Lastly, [systemd-journald(8)](https://www.freedesktop.org/software/systemd/man/systemd-journald.html) writes the system’s journal in binary form to `/var/log/journal/{machine-id}`; if (locally) persisting the entire log is desired, it is recommended to make all of `/var/log/journal` persistent.

If not, one can set `Storage=volatile` in [journald.conf(5)](https://www.freedesktop.org/software/systemd/man/journald.conf.html) ([`services.journald.storage = "volatile";`](options.html#opt-services.journald.storage)), which disables journal persistence and causes it to be written to `/run/log/journal`.
