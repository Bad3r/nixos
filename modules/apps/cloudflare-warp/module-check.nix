/*
  Check: force the enrolled branch of the Cloudflare WARP app module.

  CI has no secrets submodule, so every host closure takes the un-enrolled
  branch and nothing evaluates the sops declarations or the mdm.xml template.
  A fixture secrets root holding a non-secret cloudflare-warp.yaml, together
  with hostName = "tpnix" (a registry host whose sopsRuntimeReady is true),
  forces the enrolled branch here. A missing fixture root and a host outside
  the registry cover both warning paths in the same check.
*/
{
  lib,
  inputs,
  nixosAppHelpers,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks."apps/cloudflare-warp-module-eval" =
        let
          # The module argument, not config.flake.lib.nixos: the helper read
          # back through the flake.lib option merge is a wrapper whose
          # functionArgs are empty, so the module system could not inject pkgs.
          warpModule = nixosAppHelpers.getApp "cloudflare-warp";
          mkNixos =
            {
              secretsRoot,
              serviceMode ? "warp",
              hostName ? "tpnix",
            }:
            inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                inputs.sops-nix.nixosModules.sops
                warpModule
                {
                  nixpkgs.config.allowUnfree = true;
                  programs.cloudflare-warp.extended = {
                    enable = true;
                    inherit serviceMode;
                  };
                  # Module output only, never decryption: the fixture is not
                  # a sops file.
                  sops.validateSopsFiles = false;
                  sops.age.keyFile = "/dev/null";
                  system.stateVersion = "26.05";
                }
              ];
              specialArgs = {
                inherit hostName secretsRoot;
              };
            };
          enrolled = mkNixos {
            secretsRoot = ./module-check-fixtures;
            serviceMode = "tunnelonly";
          };
          unenrolled = mkNixos { secretsRoot = "${./module-check-fixtures}/missing"; };
          unregistered = mkNixos {
            secretsRoot = ./module-check-fixtures;
            hostName = "unregistered";
          };
          template = enrolled.config.sops.templates."cloudflare-warp-mdm";
          secretOf = name: enrolled.config.sops.secrets."cloudflare-warp/${name}";
          placeholderOf = name: enrolled.config.sops.placeholder."cloudflare-warp/${name}";
          renders = text: lib.hasInfix text template.content;
          # Whitespace-free so a key and its value can be matched as one
          # string: a swap between two <string> bodies survives every
          # single-element match.
          packed = lib.replaceStrings [ "\n" " " ] [ "" "" ] template.content;
          pairs = name: lib.hasInfix "<key>${name}</key><string>${placeholderOf name}</string>" packed;
          check = name: cond: lib.assertMsg cond "apps/cloudflare-warp-module-eval: ${name}";
        in
        assert check "organization pairs with its placeholder" (pairs "organization");
        assert check "auth_client_id pairs with its placeholder" (pairs "auth_client_id");
        assert check "auth_client_secret pairs with its placeholder" (pairs "auth_client_secret");
        assert check "service_mode follows the option" (renders "<string>tunnelonly</string>");
        assert check "auto_connect is 0" (renders "<integer>0</integer>");
        assert check "template stays on the sops tmpfs" (
          template.path == "/run/secrets/rendered/cloudflare-warp-mdm"
        );
        assert check "unit bind-mounts the render into the WARP state directory" (
          lib.elem "${template.path}:/var/lib/cloudflare-warp/mdm.xml" enrolled.config.systemd.services.cloudflare-warp.serviceConfig.BindReadOnlyPaths
        );
        assert check "template is root-only" (template.mode == "0600");
        assert check "template restarts warp-svc" (template.restartUnits == [ "cloudflare-warp.service" ]);
        assert check "organization key" ((secretOf "organization").key == "organization");
        assert check "auth_client_id key is per host" (
          (secretOf "auth_client_id").key == "tpnix/auth_client_id"
        );
        assert check "auth_client_secret key is per host" (
          (secretOf "auth_client_secret").key == "tpnix/auth_client_secret"
        );
        assert check "enrolled host runs the service" enrolled.config.services.cloudflare-warp.enable;
        assert check "enrolled host keeps the upstream UDP opening off" (
          !enrolled.config.services.cloudflare-warp.openFirewall
        );
        assert check "enrolled host does not warn" (
          !lib.any (lib.hasInfix "Cloudflare WARP enrollment is disabled on") enrolled.config.warnings
        );
        assert check "missing secret leaves the service off" (
          !unenrolled.config.services.cloudflare-warp.enable
        );
        assert check "missing secret warns" (
          lib.any (lib.hasInfix "secrets/cloudflare-warp.yaml is missing") unenrolled.config.warnings
        );
        assert check "host outside the registry leaves the service off" (
          !unregistered.config.services.cloudflare-warp.enable
        );
        assert check "host outside the registry warns" (
          lib.any (lib.hasInfix "sopsRuntimeReady is false") unregistered.config.warnings
        );
        assert check "host outside the registry renders no template" (
          !(unregistered.config.sops.templates ? "cloudflare-warp-mdm")
        );
        pkgs.runCommandLocal "cloudflare-warp-module-eval-ok" { } "touch $out";
    };
}
