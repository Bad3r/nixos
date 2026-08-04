/*
  firefoxpwa: userdata directory pinning
  Description: Whenever programs.firefoxpwa.extended.enable is set, pins the
    firefoxpwa userdata directory into the session and hardens it to 0700, for
    every site the browser extension installs, not just any one site this repo
    also manages declaratively (see ./dmail.nix for the DMail-specific install
    layered on top of this).
*/
_: {
  flake.homeManagerModules.browsers.firefoxpwa =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    let
      firefoxpwaEnabled = osConfig.programs.firefoxpwa.extended.enable or false;
    in
    {
      options.programs.firefoxpwa.dataDir = lib.mkOption {
        type = lib.types.str;
        internal = true;
        readOnly = true;
        default = "${config.xdg.dataHome}/firefoxpwa";
        description = "Directory pinned and hardened for every firefoxpwa site.";
      };

      config = lib.mkIf firefoxpwaEnabled (
        let
          dataDir = config.programs.firefoxpwa.dataDir;
        in
        {
          # firefoxpwa resolves its userdata tree, and system integration its
          # applications/ directory, from the session environment: the
          # generated .desktop launcher runs `firefoxpwa site launch`, the
          # browser extension starts `firefoxpwa connector`, and the desktop
          # menu that has to find a launcher entry resolves the directory to
          # scan independently of what wrote it. Both readers are shared with
          # every site installed from the browser extension, so tying the
          # directory to a narrower toggle would move it out from under those
          # sites whenever that toggle changed. XDG_DATA_HOME is also defined by
          # Home Manager's own xdg module wherever xdg.enable is true (system76,
          # through pentesting-devshell): both definitions are config.xdg.dataHome,
          # so types.str's mergeEqualOption accepts them. Any other value here is
          # an eval conflict on that host, not an override.
          home.sessionVariables = {
            FFPWA_USERDATA = dataDir;
            XDG_DATA_HOME = config.xdg.dataHome;
          };

          # config.json under dataDir holds start_url for every site the
          # browser extension installs, and firefoxpwa writes it through
          # File::create with no mode of its own, under a parent left however
          # it was created. Same treatment and ordering as
          # modules/home/gecko-secrets.nix.
          home.activation.ensureFirefoxpwaSecretDir =
            lib.hm.dag.entryBetween [ "sops-nix" ] [ "writeBoundary" ]
              ''
                install -d -m 700 '${dataDir}'
              '';
        }
      );
    };
}
