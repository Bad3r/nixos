{
  config,
  lib,
  secretsRoot,
  ...
}:
let
  parts = map (part: secretsRoot + "/fonts/windows-office.tar.zst.part-${part}") [
    "00"
    "01"
  ];
  complete = builtins.all builtins.pathExists parts;
  fontPackages = config.flake.lib.fonts.packages;
in
{
  nixpkgs.allowedUnfreePackages = [
    "vista-fonts"
    "windows-office-fonts"
  ];
  flake.nixosModules.hosts-common.imports = [
    ({ pkgs, ... }: {
      assertions = [
        {
          assertion = !(builtins.any builtins.pathExists parts) || complete;
          message = "Windows/Office font archive is incomplete; initialize the secrets submodule at its pinned commit.";
        }
      ];
      fonts.packages = [
        pkgs.vista-fonts
      ]
      ++ lib.optional complete (fontPackages pkgs).windows-office-fonts;
      fonts.fontconfig.confPackages = lib.optional complete (
        pkgs.writeTextDir "etc/fonts/conf.d/52-windows-office.conf" ''
          <?xml version="1.0"?>
          <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
          <fontconfig>
            <!-- Candara Light reports normal weight, which otherwise lets it
                 win regular Candara requests over the vista-fonts face. -->
            <match target="scan">
              <test name="family" compare="eq"><string>Candara Light</string></test>
              <edit name="weight" mode="assign"><const>light</const></edit>
            </match>
          </fontconfig>
        ''
      );
    })
  ];
}
