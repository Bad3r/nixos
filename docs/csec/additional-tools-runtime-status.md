# Additional Tools: Runtime Smoke-Test Status

Companion report for `docs/csec/additional-tools-reference.md`. Each tool's
documented `run` command was invoked with a help or version flag (placeholders
such as `$target`, `$url`, `$domain` substituted) under a 60-second timeout to
confirm the package could launch on the `flake.lock` state used for the smoke
test.

The runtime smoke test was run on 2026-05-04 against the active flake pin at
that time, and the inventory and summary below were reconciled on 2026-08-01
against the companion reference without re-executing anything.

The only entries re-run since are the nine the 2026-05-04 snapshot recorded
under "build or evaluation error"; all 118 others still carry their 2026-05-04
result. Those nine were re-run in two batches. Five cleared and one was
reclassified, taking the group from nine entries to three and "run as
documented" from 95 to 100.

`mitm6` and `maigret` were re-verified on 2026-07-23 under Python 3.14.6 and
now run as documented: upstream `mitm6` dropped its `future` dependency
(closure is netifaces / scapy / twisted only) and `maigret` migrated the
insecure `pypdf2-3.0.1` to `pypdf-6.14.2`, clearing the two evaluation blocks
recorded earlier.

The remaining seven were re-run on 2026-08-04 against the current pin
(python3 3.14.6). Three cleared and one was reclassified:

- `dc3dd` now builds and runs; the recorded gcc failure is gone.
- `evil-winrm` was fixed by `Bad3r/nixpkgs@807b1085` (3.7 -> 3.9), whose
  regenerated Bundler environment adds the `csv`, `benchmark` and `syslog` gems
  that Ruby unbundled.
- `waybackurls` was blocked only by an incorrect `unfree` placeholder license,
  corrected in `Bad3r/nixpkgs@a71f346e` (waybackurls is MIT), so it now runs
  with no override.
- `patator` still fails, but on a different dependency than the one recorded.

`maltego` was never a build defect either; it is genuinely unfree and gets its
own category.

## Summary

| Result                                                           | Count   |
| ---------------------------------------------------------------- | ------- |
| ✅ Run as documented                                             | 100     |
| ⚠️ Documented as unavailable in the reference                    | 10      |
| ⚠️ Build or evaluation error                                     | 3       |
| ⚠️ Blocked by the unfree license gate                            | 1       |
| ⚠️ Binary path mismatch in the documented attribute              | 5       |
| ⚠️ Documented attribute resolves to a different upstream project | 2       |
| ⚠️ Documented smoke flag incompatible with the binary            | 2       |
| ⚠️ External (non-nixpkgs) toolchain blocked                      | 1       |
| ⚠️ Closure too large for smoke budget                            | 1       |
| ⚠️ Documented uvx / PyPI invocation broken                       | 2       |
| **Total entries in the reference**                               | **127** |

The reference doc flags each unavailable tool inline (the entry's `run..:`
field carries text such as `Not in nixpkgs ...` or `Must create a custom nixpkg`); there is no dedicated section for them. The groupings below are
this report's, collected by the underlying reason for the failure.

The five tools promoted into `docs/csec/toolkit.md` (katana, gau, gowitness,
nikto, and wafw00f) are intentionally absent from this report because they are
no longer entries in the companion reference.

## ✅ Tools that run as documented

### Active Directory and Windows

- ✅ netexec
- ✅ bloodhound
- ✅ bloodhound-py
- ✅ responder
- ✅ certipy
- ✅ mitm6
- ✅ enum4linux-ng
- ✅ smbmap
- ✅ adidnsdump
- ✅ ldapdomaindump
- ✅ donpapi
- ✅ evil-winrm (`-h` writes usage only to a TTY; piped or redirected it exits 0 silently)

### Network Reconnaissance and Enumeration

- ✅ rustscan
- ✅ theharvester
- ✅ sherlock
- ✅ maigret
- ✅ bettercap
- ✅ ettercap
- ✅ hping (binary `hping3`)
- ✅ interactsh
- ✅ dnsrecon
- ✅ massdns
- ✅ shuffledns
- ✅ httprobe
- ✅ cero
- ✅ chaos
- ✅ dnstwist
- ✅ shodan
- ✅ censys
- ✅ holehe
- ✅ recon-ng
- ✅ arp-scan (root needed for actual scans; `--help` works without sudo)
- ✅ netdiscover (no `--help`/`-h`; usage prints on invalid flags; root needed for scans)
- ✅ fping
- ✅ onesixtyone (no `--help`/`-h`; usage prints on invalid flags)
- ✅ net-snmp (`snmpwalk -h`)
- ✅ ike-scan
- ✅ swaks
- ✅ samba (`smbclient --help`; do not append `-- --help`, the wrapper passes `--` literally)

### Web Application Testing

- ✅ dalfox
- ✅ arjun
- ✅ unfurl
- ✅ qsreplace
- ✅ meg
- ✅ wuzz
- ✅ paramspider (uvx)
- ✅ commix
- ✅ joomscan
- ✅ gospider
- ✅ hakrawler
- ✅ photon
- ✅ waybackurls

### Credential Attacks and Wordlists

- ✅ medusa
- ✅ crunch
- ✅ hashid

### Wireless Auditing

- ✅ kismet
- ✅ wifite2
- ✅ bully

### Reverse Engineering and Dynamic Analysis

- ✅ binwalk
- ✅ apktool
- ✅ chntpw (`-h` only; no `--help`)
- ✅ ropper (uvx)
- ✅ gef (gdb plugin; help command shows gdb usage)
- ✅ python3Packages.ropgadget
- ✅ upx

### Forensics, Recovery and Imaging

- ✅ sleuthkit (`fls`)
- ✅ bulk_extractor
- ✅ scalpel
- ✅ dcfldd
- ✅ safecopy
- ✅ chainsaw
- ✅ dc3dd

### Cryptography, Stego and CTF

- ✅ steghide
- ✅ stegseek
- ✅ zsteg
- ✅ fcrackzip
- ✅ pdfcrack (`-h`)
- ✅ outguess

### Auditing, SAST and Vulnerability Assessment

- ✅ semgrep
- ✅ bandit

### Cloud and Container Security

- ✅ trivy
- ✅ grype
- ✅ syft
- ✅ gitleaks
- ✅ trufflehog
- ✅ prowler
- ✅ pacu
- ✅ kube-bench
- ✅ kube-hunter
- ✅ dive
- ✅ dockle
- ✅ clair
- ✅ checkov
- ✅ tfsec
- ✅ kubescape
- ✅ steampipe

### Pivoting and Tunneling

- ✅ chisel
- ✅ proxychains-ng
- ✅ gost
- ✅ frp (binaries `frpc` / `frps`; use `nix shell nixpkgs#frp -c frpc -h`)

## ⚠️ Failures grouped by issue

### Documented as not in nixpkgs

The reference itself flags these. Listed for completeness.

- ⚠️ crackmapexec (project archived; reference instructs using `netexec`)
- ⚠️ gf (nixpkgs `gf` is an unrelated GDB frontend)
- ⚠️ anew (closest match `anewer` is unrelated)
- ⚠️ wifite (Python 2 EOL; reference instructs using `wifite2`)
- ⚠️ reaver

### Documented as needing a local custom package

- ⚠️ pwndbg (reference: `Must create a custom nixpkg`)
- ⚠️ velociraptor (reference: `Must create a custom nixpkg`)
- ⚠️ falco (reference: `Must create a custom nixpkg`)
- ⚠️ cmseek (reference shows `git clone ... && uv run python3 cmseek.py`; no PyPI entry point)
- ⚠️ xsstrike (reference shows `git clone ... && uv run python xsstrike.py`; no PyPI entry point)

### Build or evaluation error

Re-verified 2026-08-04 under python3 3.14.6.

- ⚠️ droopescan (uvx): runtime crash, `cement 2.6.2` imports the `imp` module
  that Python 3.12 removed. Unchanged under 3.14.
- ⚠️ patator (uvx): the recorded `cx-oracle` cause no longer applies. The
  install now fails building transitive `mysqlclient 2.2.8`, whose setup
  script aborts with `Can not find valid pkg-config name` because no MySQL
  client library is on the `uvx` build path.
- ⚠️ python3Packages.angr: wheel preparation aborts with
  `angr requires setuptools-rust to build`, which is missing from
  `nativeBuildInputs`. Tracked upstream as
  [NixOS/nixpkgs#501379](https://github.com/NixOS/nixpkgs/issues/501379),
  which covers the `python314Packages.angr` job.

### Blocked by the unfree license gate

The package builds and runs; the only blocker is policy. Add it to
`modules/meta/nixpkgs-allowed-unfree.nix` for repo configs, or pass
`NIXPKGS_ALLOW_UNFREE=1` with `--impure` for a one-off. Re-verified
2026-08-04.

- ⚠️ maltego: unfree license. `NIXPKGS_ALLOW_UNFREE=1 nix build --impure nixpkgs#maltego` completes.

### Binary path mismatch in the documented attribute

The package builds, but the binary referenced by the run command does not
exist (or `meta.mainProgram` is wrong).

- ⚠️ python3Packages.impacket: nixpkgs ships `secretsdump.py`, `psexec.py`,
  etc. The reference's `impacket-secretsdump` alias does not exist. Use
  `nix shell nixpkgs#python3Packages.impacket -c secretsdump.py --help`.
- ⚠️ eyewitness: derivation builds, but `bin/eye-witness` is missing inside
  the store path. `nix run` fails with `No such file or directory`.
- ⚠️ volatility3: binaries are `vol` and `volshell`, not `volatility3`. Also
  unfree, requires `NIXPKGS_ALLOW_UNFREE=1 --impure`. Use
  `nix shell --impure nixpkgs#volatility3 -c vol --help`.
- ⚠️ ligolo-ng: package contains `ligolo-proxy` and `ligolo-agent`; no
  `ligolo-ng` binary. Use `nix shell nixpkgs#ligolo-ng -c ligolo-proxy --help`.
- ⚠️ pwntools: `meta.mainProgram` is unset, the binary is `pwn`. `nix run nixpkgs#pwntools` fails. Use `nix shell nixpkgs#pwntools -c pwn --help`.

### Documented attribute resolves to a different upstream project

- ⚠️ hayabusa: nixpkgs `hayabusa` is the IPC daemon by `koutoftimer`, not the
  Yamato Security Windows EVTX Sigma scanner. The
  `csv-timeline -d $evtx_dir -o timeline.csv` flags do not apply. Treat the
  intended forensics tool as needing a custom package.
- ⚠️ kerbrute: nixpkgs `kerbrute` resolves to impacket's Python kerbrute, not
  ropnop's Go tool. The reference's
  `kerbrute userenum -d $domain users.txt` syntax targets the ropnop binary
  and does not match the impacket CLI. The binary launches, but the
  documented command form does not.

### Documented smoke flag incompatible with the binary

- ⚠️ hash-identifier: no `--help` / `-h` support. The tool is purely
  interactive and reads HASH from stdin.
- ⚠️ python3Packages.scapy: entry point loads, but `--help` is rejected by
  scapy's own option parser (`option --help not recognized`). Use
  `python -c 'from scapy.all import *'` for verification.

### External (non-nixpkgs) toolchain blocked

- ⚠️ subzy: `go run github.com/PentestPad/subzy@latest` fails with
  `unknown GOEXPERIMENT synctest` against the system `go`. Not packaged in
  nixpkgs.

### Documented uvx / PyPI invocation broken

- ⚠️ spiderfoot: `uvx --from spiderfoot sf` fails. The package is not on
  PyPI under that name (`spiderfoot-py` is also missing) and there is no
  `spiderfoot` attribute in nixpkgs. Pull from upstream git or install
  manually.
- ⚠️ scoutsuite: the package's CLI entry point is `scout`, not `scoutsuite`.
  The reference's `uvx scoutsuite` form fails. Use
  `uvx --from scoutsuite scout --help`.

### Closure fetch exceeded the smoke-test budget

- ⚠️ autopsy: 1.4 GiB closure (autopsy plus openjdk-21) did not finish
  downloading within a 20-minute budget on the test connection. Fetch is
  functional, just slow. Not a tool defect.

## Notes for the upstream reference

Run-command corrections that would prevent a future smoke run from
regressing on these entries:

- `impacket`: invoke the canonical `secretsdump.py` script names rather
  than `impacket-secretsdump`.
- `volatility3`: invoke `vol` (or `volshell`) and prefix with
  `NIXPKGS_ALLOW_UNFREE=1` / `--impure`.
- `ligolo-ng`: use `ligolo-proxy` / `ligolo-agent` rather than the bare
  attribute.
- `pwntools`: invoke `pwn` (`nix shell nixpkgs#pwntools -c pwn --help`)
  rather than `nix run nixpkgs#pwntools`.
- `scoutsuite` (uvx): use `uvx --from scoutsuite scout ...`.
- `kerbrute`: clarify that nixpkgs ships impacket's Python kerbrute, or
  package ropnop's Go tool to match the documented command form.
- `hayabusa`: nixpkgs `hayabusa` is a different project; document the
  Yamato Security EVTX Sigma scanner as needing a custom package.
- `frp`: the package has no default app; document it as `nix shell nixpkgs#frp -c frpc -c frpc.toml` (or `frps`).
