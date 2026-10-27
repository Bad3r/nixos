{ lib, secretsRoot, ... }:
let
  archiveHashes = builtins.fromJSON (builtins.readFile ../security/_font-archive-hashes.json);
  checkedArchive =
    archive:
    if
      builtins.readFileType archive == "regular"
      && builtins.hashFile "sha256" archive == archiveHashes."fonts/${baseNameOf archive}"
    then
      archive
    else
      throw "Private font archive ${baseNameOf archive} does not match its reviewed hash; verify the asset before updating modules/security/_font-archive-hashes.json.";
  officeParts = map (part: secretsRoot + "/fonts/windows-office.tar.zst.part-${part}") [
    "00"
    "01"
  ];
  monolisaArchive = secretsRoot + "/fonts/monolisa.tar.zst";
  checkedMonolisaArchive = checkedArchive monolisaArchive;
  checkedOfficeParts = map checkedArchive officeParts;
  fontPackages =
    pkgs:
    lib.optionalAttrs (builtins.pathExists monolisaArchive) {
      monolisa = pkgs.callPackage ../../packages/private-fonts {
        pname = "monolisa";
        version = "3.0";
        archives = [ checkedMonolisaArchive ];
        fontRoot = "monolisa";
        requiredFamilies = [
          "MonoLisaCode"
          "MonoLisaText"
        ];
        documentation = [ "monolisa/README.md" ];
      };
    }
    // lib.optionalAttrs (builtins.all builtins.pathExists officeParts) {
      windows-office-fonts = pkgs.callPackage ../../packages/private-fonts {
        pname = "windows-office-fonts";
        version = "2026-10-27";
        archives = checkedOfficeParts;
        fontRoot = "fonts";
        requiredFamilies = [
          "Aptos"
          "Aptos Slab"
          "Georgia Pro"
          "Verdana Pro"
          "Wingdings 2"
          "Wingdings 3"
          "MT Extra"
        ];
        checkManifest = true;
        # The source faces report normal weight despite their Light names.
        fontWeights = {
          "Candara-Light.ttf" = 300;
          "Candara-LightItalic.ttf" = 300;
        };
        documentation = [
          "licenses"
          "FONT-CATALOG.tsv"
          "FAMILIES.txt"
        ];
      };
    };
in
{
  options.flake.lib.fonts.packages = lib.mkOption {
    type = lib.types.raw;
    description = "Build private font packages with the supplied nixpkgs instance.";
  };
  options.flake.lib.fonts.officeParts = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    description = "Archive parts used by the private Office font package.";
  };
  config = {
    flake.lib.fonts.packages = fontPackages;
    flake.lib.fonts.officeParts = officeParts;
    perSystem = { pkgs, ... }: { packages = fontPackages pkgs; };
  };
}
