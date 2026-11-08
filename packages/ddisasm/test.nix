{
  runCommandCC,
  ddisasm,
}:

runCommandCC "ddisasm-roundtrip"
  {
    nativeBuildInputs = [ ddisasm ];
  }
  ''
    cat > fixture.c <<'EOF'
    #include <stdio.h>
    int main(void) {
      puts("ddisasm roundtrip");
      return 0;
    }
    EOF
    cc -O1 -fno-pie -no-pie fixture.c -o original
    cp original original.saved
    ddisasm original --ir fixture.gtirb --asm fixture.s -j 1
    test -s fixture.gtirb
    test -s fixture.s
    cmp original original.saved
    cc -nostartfiles -no-pie fixture.s -o rebuilt
    ./original > expected
    ./rebuilt > actual
    cmp expected actual
    grep -Fx 'ddisasm roundtrip' actual
    mkdir "$out"
    cp fixture.gtirb fixture.s expected actual "$out/"
  ''
