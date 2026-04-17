/*
  Package: ungoogled-chromium
  Description: Chromium build with Google-integration stripped out, prioritizing privacy and manual control over updates.
  Homepage: https://ungoogled-software.github.io/ungoogled-chromium/
  Documentation: https://github.com/ungoogled-software/ungoogled-chromium
  Repository: https://github.com/ungoogled-software/ungoogled-chromium

  Summary:
    * Ships Chromium without Google web services, binaries, or background request endpoints, reducing unsolicited network traffic.
    * Exposes policy support and flags identical to upstream Chromium so administrators can enforce hardened defaults.

  Options:
    --incognito: Launch directly into an incognito session.
    --ozone-platform-hint=auto: Allow Wayland/X11 negotiation at runtime on Linux.
    --enable-features=VaapiVideoDecoder,VaapiVideoEncoder: Turn on VA-API hardware acceleration where supported.
    --profile-directory=<name>: Use a specific profile directory under `~/.config/chromium`.

  Example Usage:
    * `ungoogled-chromium https://example.com` -- Open a URL with the de-Googled Chromium fork.
    * `ungoogled-chromium --incognito --enable-features=VaapiVideoDecoder` -- Launch a private session with VA-API decoding.
    * `ungoogled-chromium --user-data-dir ~/.local/share/chromium-alt` -- Keep a fully isolated profile tree for testing.
*/
_:
let
  UngoogledChromiumModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."ungoogled-chromium".extended;

      managedExtensionSettings = {
        "ddkjiahejlhfcafbddmgiahcphecmpfh" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
        "nngceckbapebfimnlniiiahkandclblb" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
      };

      managedDefaultSearchProvider = {
        DefaultSearchProviderEnabled = true;
        DefaultSearchProviderName = "Google";
        DefaultSearchProviderKeyword = "google.com";
        DefaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}&hl=en&gl=US&pws=0&safe=off";
        DefaultSearchProviderSuggestURL = "https://www.google.com/complete/search?hl=en&gl=US&client=chrome&q={searchTerms}";
        DefaultSearchProviderIconURL = "https://www.google.com/favicon.ico";
        DefaultSearchProviderEncodings = [ "UTF-8" ];
      };

      chromiumWebStoreSrc = pkgs.fetchFromGitHub {
        owner = "NeverDecaf";
        repo = "chromium-web-store";
        rev = "v1.5.5.3";
        hash = "sha256-/pJVNVTjLS3ZaeSkhS9ltCtEH237gVqCnb4S1f/yfD0=";
      };

      extensionPaths =
        lib.optional cfg.enableWebStoreExtension "${chromiumWebStoreSrc}/src" ++ cfg.extensions;

      wrappedFlags =
        lib.optional (extensionPaths != [ ]) "--load-extension=${lib.concatStringsSep "," extensionPaths}"
        ++ lib.optional cfg.enableWebStoreExtension "--extension-mime-request-handling=always-prompt-for-install"
        ++ cfg.extraFlags;

      customizedPackage = pkgs.symlinkJoin {
        name = "${cfg.package.pname or "ungoogled-chromium"}-wrapped";
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];

        postBuild = ''
          wrapProgram $out/bin/chromium \
            ${lib.concatMapStringsSep " \\\n            " (
              flag: "--add-flags ${lib.escapeShellArg flag}"
            ) wrappedFlags}
        '';
      };
    in
    {
      options.programs.ungoogled-chromium.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ungoogled-chromium.";
        };

        package = lib.mkPackageOption pkgs "ungoogled-chromium" { };

        finalPackage = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = ''
            Resulting customized ungoogled-chromium package.
          '';
        };

        enableWebStoreExtension = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to load the Chromium Web Store extension by default.
          '';
        };

        extensions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Additional unpacked Chromium extension directories to load.
            Paths should be strings pointing to unpacked extension directories.
          '';
          example = lib.literalExpression ''
            [
              "/path/to/unpacked/extension"
              "''${pkgs.some-extension}/src"
            ]
          '';
        };

        extraFlags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Additional command-line flags to pass to Chromium.
          '';
          example = lib.literalExpression ''
            [
              "--start-maximized"
              "--enable-features=VaapiVideoDecoder"
            ]
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        programs.ungoogled-chromium.extended.finalPackage = customizedPackage;
        environment = {
          systemPackages = [ cfg.finalPackage ];
          etc."chromium/policies/managed/extension-settings.json".text = builtins.toJSON {
            ExtensionSettings = managedExtensionSettings;
          };
          etc."chromium/policies/managed/default-search-provider.json".text =
            builtins.toJSON managedDefaultSearchProvider;
        };
      };
    };
in
{
  flake.nixosModules.apps.ungoogled-chromium = UngoogledChromiumModule;
}
