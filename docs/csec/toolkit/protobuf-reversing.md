# Pentesting Toolkit: Protobuf Reversing

[Back to Pentesting Toolkit](../toolkit.md)

## Protobuf Reversing

- blackboxprotobuf
  - run..: `bbpb < $message.bin > message.json`, then `bbpb -e < message.json > edited.bin`
  - Repo.: <https://github.com/nccgroup/blackboxprotobuf>
  - Docs.: <https://github.com/nccgroup/blackboxprotobuf/blob/master/lib/CLI.md>
  - Desc.: Decodes Protobuf messages without a schema into JSON plus an inferred type definition, and re-encodes edited JSON. Installed from nixpkgs `python3Packages.bbpb`.
- buf
  - run..: `buf lint` in a directory of `.proto` files
  - Repo.: <https://github.com/bufbuild/buf>
  - Docs.: <https://buf.build/docs/>
  - Desc.: Protobuf toolchain for linting, formatting, breaking-change detection, and code generation.
- pbtk
  - run..: `pbtk` for the GUI; `pbtk-jar-extract $apk out/` and `pbtk-from-binary $binary out/` from the shell
  - Repo.: <https://github.com/marin-m/pbtk>
  - Docs.: <https://github.com/marin-m/pbtk#readme>
  - Desc.: Extracts `.proto` definitions from APK, JAR, and DEX files and from binaries that embed Protobuf reflection metadata, then edits, replays, and fuzzes messages against network endpoints. Data lives under `~/.pbtk/`. Packaged locally in [`packages/pbtk`](../../../packages/pbtk/default.nix) with nixpkgs `protoc` and dex2jar. The package ships upstream's closed-source Jad decompiler, which makes it unfree.
- protobuf
  - run..: `protoc --decode_raw < $message.bin`
  - Repo.: <https://github.com/protocolbuffers/protobuf>
  - Docs.: <https://protobuf.dev/>
  - Desc.: Protocol Buffers compiler `protoc`; generates code from `.proto` schemas and decodes schemaless captured messages with `--decode_raw`.
