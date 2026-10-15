# HDiffPatch

`hdiffz` writes a delta between two files or two directories, and `hpatchz` applies it.
Two jobs come up in binary work: seeing what moved between two builds of the same program, and reconstructing a withheld file from a published delta.
`hpatchz` also reads bsdiff and VCDIFF patches, so one binary covers deltas made by bsdiff, xdelta3, and open-vcdiff.

Upstream: <https://github.com/sisong/HDiffPatch>

## Getting the tools

nixpkgs has no `hdiffpatch` attribute, so the binaries come from a release archive.
Release archives cover linux64, linux arm32 and arm64, riscv32 and riscv64, loong64, macOS, and Windows.
The linux64 pair is statically linked, so it runs on NixOS without patchelf.

```sh
cd "$(mktemp -d)"
gh release download -R sisong/HDiffPatch -p '*_bin_linux64.zip'
unzip -j -d bin ./*_bin_linux64.zip
./bin/hpatchz -v
```

A source build wants the sibling compression and hash repositories named in the upstream readme cloned beside the checkout, then `make -j`.

## Delta formats

| Format         | Written by      | Leading bytes      |
| -------------- | --------------- | ------------------ |
| HDIFF13        | default         | `HDIFF13&`         |
| HDIFFSF20      | `-SD`           | `HDIFFSF20&`       |
| HDIFFW26       | `-WD`           | `HDIFFW26`         |
| HDIFF19        | directory input | `HDIFF19&`         |
| BSDIFF40       | `-BSD`          | `BSDIFF40`         |
| endsley/bsdiff | `-BSD -SD`      | `ENDSLEY/BSDIFF43` |
| VCDIFF         | `-VCD`          | `d6 c3 c4`         |

`hpatchz -info $delta` names the format, the saved old and new sizes, the compressor, and the checksum type, which identifies a delta file that arrived without a name.
`file` knows only the bsdiff and VCDIFF outputs, and every HDIFF format reads as `data`, so match the leading bytes instead.
`-WD` defaults to zstd compression with an xxh128 checksum and is the one format whose patch step runs multi-threaded.

## Creating a delta

```sh
hdiffz -s-64 -WD $old $new $delta
```

Default `-m` mode holds the new file plus five times the old file in memory, and nine times past a 2 GB old file.
`-s-64` streams the old file instead, for a bounded footprint and a slightly larger delta.
`hdiffz` re-applies the delta it just wrote as a self-check, which `-d` skips.
An empty old path, passed as `""`, turns the run into plain compression of the new file.

## Applying a delta

```sh
hpatchz $old $delta $out
```

An output path that already exists stops the run with exit 12 unless `-f` overwrites it.
An empty old path unpacks a delta that was written as plain compression.
A single-file patch writes a non-executable file, so a reconstructed executable needs `chmod +x`.
Directory patching restores the executable bit and nothing else: timestamps, ownership, and symlinks sit outside the format.

## Wrong base file

The old file is the input the patcher cannot derive, and each format catches a different amount of substitution.

- A size mismatch is refused before any output under HDIFF13, HDIFFSF20, and HDIFFW26, with exit 6 and both sizes printed.
- An altered base of the same size trips only `-WD`, whose xxh128 checksum over the new data exits 106 and leaves the corrupt output on disk.
- `-C-all` extends checksumming to the old and diff data, which reports the same case as exit 105 against the old data.
- bsdiff and VCDIFF deltas carry no old-file checksum, so a same-size wrong base yields a corrupt output with exit 0.
- `hdiffz -t $old $new $delta` re-applies an existing delta and compares, exiting 7 on mismatch.

An exit 0 is evidence only where the format carries a checksum; otherwise hash the output against a known value.

## Patches from other tools

`hpatchz` applies bsdiff 4.3 output, and xdelta3 output built with the default, `none`, or `lzma` secondary compressor.
The `djw` and `fgk` secondary compressors exit 10 as an unsupported VCDIFF compress id, so decode those with xdelta3 itself.
In the other direction, `-BSD` and `-VCD` deltas feed bspatch, xdelta3, and open-vcdiff.

## Directory deltas

A directory on either side switches `hdiffz` to HDIFF19, where one delta covers added, removed, and changed files.
`hpatchz -info` on such a delta prints the file counts, how many files copy out of the old tree untouched, and the referenced byte totals, which summarizes a release diff before any patching.
`-g#$pattern` drops matching paths from the comparison, keeping caches and version-control directories out of the delta.
