/*
  Shell function: memcheck

  Description:
    Prints a snapshot of /proc/meminfo with values in GiB. Mirrors
    `free -h` but uses the kernel's authoritative source and includes
    Slab/SReclaimable so reclaimable kernel caches are visible. Read
    `MemAvailable` rather than `MemFree` for the practical free
    figure: it accounts for reclaimable page cache and slab in
    addition to truly unused pages.

  Usage:
    memcheck

  Example:
    $ memcheck
    MemTotal:        30.69 GiB
    MemFree:          7.19 GiB
    MemAvailable:    24.80 GiB
    Buffers:          3.31 GiB
    Cached:          13.00 GiB
    SwapTotal:       31.98 GiB
    SwapFree:        31.98 GiB
    Slab:             2.29 GiB
    SReclaimable:     1.91 GiB

  Notes:
    * `/proc/meminfo` labels values in `kB`, but each unit is 1024
      bytes (KiB), a kernel quirk older than the IEC binary prefixes.
      Dividing by 1024*1024 therefore produces true GiB.
    * Wired through `environment.interactiveShellInit`, which NixOS
      folds into both `programs.bash.interactiveShellInit` and
      `programs.zsh.interactiveShellInit`. The function body is a
      single `awk` pipeline, so it is shell-agnostic.
    * Output uses `%7.2f` so the GiB column right-aligns up to four
      digits before the decimal point (covers values up to 9999 GiB).
    * Field names are highlighted (bold red, matching `grep`'s
      default `mt=01;31`) when stdout is a TTY; redirecting to a
      file or piping to another tool emits plain text via the same
      `[ -t 1 ]` gate `grep --color=auto` uses.
*/
{
  flake.nixosModules.base = {
    environment.interactiveShellInit = ''
      # memcheck - print /proc/meminfo with values in GiB.
      memcheck() {
        local _memcheck_color="" _memcheck_reset=""
        if [ -t 1 ]; then
          _memcheck_color=$'\033[01;31m'
          _memcheck_reset=$'\033[0m'
        fi
        awk -v c="$_memcheck_color" -v r="$_memcheck_reset" '
          /^(MemTotal|MemFree|MemAvailable|Buffers|Cached|Slab|SReclaimable|SwapFree|SwapTotal):/ {
            printf "%s%-15s%s %7.2f GiB\n", c, $1, r, $2/1024/1024
          }' /proc/meminfo
      }
    '';
  };
}
