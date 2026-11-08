{
  lib,
  runCommandCC,
  ghidra,
  lief,
  lief-ghidra,
}:

let
  ghidraWithLief = ghidra.withExtensions (_: [ lief-ghidra ]);
in
runCommandCC "lief-ghidra-headless"
  {
    nativeBuildInputs = [ ghidraWithLief ];
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_CACHE_HOME="$HOME/.cache"
    export LIEF_JNI_DEBUG=1
    mkdir -p "$HOME" projects scripts

    cat > fixture.c <<'EOF'
    #include <stdio.h>
    int main(void) {
      puts("LIEF Ghidra fixture");
      return 0;
    }
    EOF
    cc -O0 -fno-pie -no-pie fixture.c -o fixture
    cp fixture fixture.saved
    chmod a-w fixture

    cat > scripts/LiefSmokeTest.java <<'EOF'
    import ghidra.app.script.GhidraScript;
    import ghidra.app.util.importer.MessageLog;
    import lief.Utils;
    import lief.elf.Binary;
    import lief.ghidra.core.NativeBridge;
    import lief.ghidra.plugins.analyzers.elf.RelocationsAnalyzer;

    public class LiefSmokeTest extends GhidraScript {
        @Override
        public void run() throws Exception {
            NativeBridge.init();
            if (!NativeBridge.isLoaded()) {
                throw new IllegalStateException("LIEF native bridge did not load");
            }
            Utils.Version version = Utils.getVersion();
            String actual = String.format("%d.%d.%d", version.major(), version.minor(), version.patch());
            if (!actual.equals("${lib.getVersion lief}")) {
                throw new IllegalStateException("Unexpected native LIEF version: " + actual);
            }

            String path = currentProgram.getExecutablePath();
            if (!lief.elf.Utils.isELF(path)) {
                throw new IllegalStateException("Native ELF recognition failed");
            }
            Binary binary = Binary.parse(path);
            if (binary == null || binary.getImageBase() != currentProgram.getImageBase().getOffset()) {
                throw new IllegalStateException("Native ELF parse disagrees with Ghidra's image base");
            }
            if (!binary.getRelocations().hasNext()) {
                throw new IllegalStateException("Native ELF parse lost fixture relocations");
            }

            RelocationsAnalyzer analyzer = new RelocationsAnalyzer();
            MessageLog log = new MessageLog();
            if (!analyzer.canAnalyze(currentProgram) ||
                !analyzer.added(currentProgram, currentProgram.getMemory(), monitor, log)) {
                throw new IllegalStateException("LIEF analyzer failed: " + log);
            }
            println("LIEF_GHIDRA_SMOKE_OK version=" + actual);
        }
    }
    EOF

    if ! timeout 180 ghidra-analyzeHeadless "$PWD/projects" lief-smoke \
      -import "$PWD/fixture" -readOnly -noanalysis \
      -log "$PWD/application.log" \
      -scriptPath "$PWD/scripts" -postScript LiefSmokeTest.java \
      > headless.log 2>&1; then
      cat headless.log
      exit 1
    fi
    cat headless.log
    grep -F 'LIEF_GHIDRA_SMOKE_OK version=${lib.getVersion lief}' headless.log
    grep -F "'lief/Utils' registered" application.log
    cmp fixture fixture.saved

    mkdir -p "$out"
    cp headless.log application.log "$out/"
  ''
