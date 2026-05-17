# Workaround for nixpkgs channels that still package naabu 2.5.0.
# Remove once every actively used nixpkgs input carries v2.6.1 or newer.
_:
let
  latestVersion = "2.6.1";

  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.naabu.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (_final: prev: {
            naabu =
              if lib.versionOlder (prev.naabu.version or "0") latestVersion then
                prev.naabu.overrideAttrs (old: {
                  version = latestVersion;

                  src = prev.fetchFromGitHub {
                    owner = "projectdiscovery";
                    repo = "naabu";
                    tag = "v${latestVersion}";
                    hash = "sha256-rjGTicUzdFRpJ3VGl/eXLKGdrbuwM3jQbOd0pmknabg=";
                  };

                  vendorHash = "sha256-Qay0jAWRnK5oRfOmYLrfWFR5eOT5glcsQ9BgSr2LiS8=";

                  meta = (old.meta or { }) // {
                    changelog = "https://github.com/projectdiscovery/naabu/releases/tag/v${latestVersion}";
                  };
                })
              else
                prev.naabu;
          })
        ];
      };
    };
in
{
  flake.customOverlays.naabu = Overlay;
}
