{
  pkgs,
  codexPkg,
}:
let
  version = codexPkg.version or "unknown";
  pname = codexPkg.pname or "codex";
in
# Rewrap upstream codex so InstallContext::from_exe finds the package layout.
# Invariants required by codex-rs/install-context/src/lib.rs:
#   * $out/bin must be the parent of the resolved exe (canonicalised).
#   * $out/codex-package.json must be a regular file (contents not parsed).
# `codex-path/` and `codex-resources/` are intentionally omitted so codex falls
# back to PATH-managed tools instead of package-local resources.
pkgs.runCommandLocal "${pname}-packaged-${version}"
  {
    passthru = {
      unwrapped = codexPkg;
    };
    meta = (codexPkg.meta or { }) // {
      mainProgram = "codex";
    };
  }
  ''
    mkdir -p $out/bin

    # Copy the real ELF, not the upstream binary wrapper. current_exe() after
    # execve must canonicalise inside $out so CodexPackageLayout::from_exe
    # locates $out/codex-package.json (the trampoline would leave it pointing
    # at upstream's store path, which has no metadata file).
    cp -L ${codexPkg}/bin/.codex-wrapped $out/bin/.codex-wrapped
    chmod +w $out/bin/.codex-wrapped

    # New trampoline preserves the bubblewrap PATH prepend that upstream's
    # wrapProgram adds, so the default Linux sandbox keeps finding bwrap.
    cat > $out/bin/codex << EOF
    #!${pkgs.bash}/bin/bash -e
    PATH='${pkgs.bubblewrap}/bin'\''${PATH:+:\$PATH}
    export PATH
    exec -a "\$0" "$out/bin/.codex-wrapped" "\$@"
    EOF
    chmod +x $out/bin/codex

    # InstallContext::from_exe only checks is_file(); upstream's own tests
    # write literal `{}` here.
    printf '{}' > $out/codex-package.json
  ''
