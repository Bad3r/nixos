{ config, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      host = config.flake.nixosConfigurations.songbird.config;
      mkFixture =
        corrupt:
        pkgs.runCommand (if corrupt then "font-archive-corrupt-fixture" else "font-archive-fixture")
          {
            nativeBuildInputs = [
              pkgs.gnutar
              pkgs.zstd
            ];
          }
          ''
            mkdir -p payload/fonts "$out"
            cp ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf payload/fonts/test.ttf
            cp payload/fonts/test.ttf payload/fonts/weighted.ttf
            (cd payload; sha256sum fonts/*.ttf > SHA256SUMS)
            ${lib.optionalString corrupt ''
              chmod u+w payload/fonts/test.ttf
              printf x >> payload/fonts/test.ttf
            ''}
            tar -I zstd -cf archive.tar.zst -C payload .
            split -n 2 -d archive.tar.zst "$out/part-"
          '';
      fixture = mkFixture false;
      corruptFixture = mkFixture true;
      fixtureFonts = pkgs.callPackage ../../packages/private-fonts {
        pname = "font-package-fixture";
        version = "1";
        archives = [
          "${fixture}/part-00"
          "${fixture}/part-01"
        ];
        fontRoot = "fonts";
        requiredFamilies = [ "DejaVu Sans" ];
        checkManifest = true;
        fontWeights."weighted.ttf" = 300;
        license = pkgs.dejavu_fonts.meta.license;
      };
      badFamily = pkgs.testers.testBuildFailure (
        fixtureFonts.override {
          requiredFamilies = [ "DejaVu" ];
        }
      );
      badChecksum = pkgs.testers.testBuildFailure (
        fixtureFonts.override {
          archives = [
            "${corruptFixture}/part-00"
            "${corruptFixture}/part-01"
          ];
        }
      );
      missingRoot = pkgs.testers.testBuildFailure (
        fixtureFonts.override {
          fontRoot = "missing";
        }
      );
      privateFonts = config.flake.lib.fonts.packages pkgs;
      installedNames = map lib.getName host.fonts.packages;
    in
    {
      checks.font-packages =
        assert !(host.systemd.services ? monolisa-fonts);
        assert !(host.systemd.services ? windows-office-fonts);
        assert !(lib.any (lib.hasPrefix "fonts/") (builtins.attrNames host.sops.secrets));
        assert !(lib.hasInfix "/var/lib/fonts" host.fonts.fontconfig.localConf);
        assert lib.all (name: lib.elem name installedNames) (builtins.attrNames privateFonts);
        pkgs.runCommand "font-packages-check"
          {
            passthru.runtimeCheck = true;
            nativeBuildInputs = [
              pkgs.fontconfig
              pkgs.findutils
              pkgs.gnugrep
            ];
          }
          ''
            font=${fixtureFonts}/share/fonts/truetype/font-package-fixture/test.ttf
            cmp "$font" ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf
            test "$(fc-query -f '%{family}' "$font")" = 'DejaVu Sans'
            test "$(fc-query -f '%{weight}' ${fixtureFonts}/share/fonts/truetype/font-package-fixture/weighted.ttf)" = 50
            test "$(find ${fixtureFonts}/share/fonts -type f | wc -l)" -eq 2
            grep -Fq 'archive has no face declaring DejaVu' ${badFamily}/testBuildFailure.log
            grep -Fq 'fonts/test.ttf: FAILED' ${badChecksum}/testBuildFailure.log
            grep -Fq 'archive has no font directory missing' ${missingRoot}/testBuildFailure.log
            touch "$out"
          '';
    };
}
