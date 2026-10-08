/*
  Package: winapps
  Description: Launcher that presents programs of a Windows guest on the Linux desktop through FreeRDP RemoteApp.
  Homepage: https://github.com/winapps-org/winapps
  Documentation: https://github.com/winapps-org/winapps/blob/main/docs/libvirt.md
  Repository: https://github.com/winapps-org/winapps

  Summary:
    * Starts or resumes the libvirt guest named in ~/.config/winapps/winapps.conf, waits for its RDP port, and runs xfreerdp.
    * Reads the RDP password through the askpass command named in that file, so no password reaches the FreeRDP argument list.

  Options:
    winapps manual <executable>: Start one Windows program as a RemoteApp window.
    winapps windows: Open the full Windows desktop.
    winapps killrdp: Terminate the FreeRDP sessions the launcher started.
    winapps cleanrdp: Remove stale FreeRDP process tracking files.

  Notes:
    * Package sourced from the winapps flake (github:winapps-org/winapps), lock-only.
    * Only bin/winapps reaches PATH: the package also installs winapps-setup (setup.sh), whose connection test shares the whole home directory (+home-drive) and trusts any certificate (/cert:tofu).
    * The configuration file and the Outlook Classic desktop entry come from modules/hm-apps/winapps.nix.
    * The wrapper's PATH prefix carries FreeRDP only; virsh comes from the libvirt package that virtualisation.libvirtd installs.
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.winapps =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.winapps.extended;
      # winapps-setup stays out of the profile: setup.sh connects with +home-drive and /cert:tofu.
      launcher = pkgs.runCommandLocal "winapps-cli" { } ''
        mkdir -p $out/bin
        ln -s ${cfg.package}/bin/winapps $out/bin/winapps
      '';
    in
    {
      options.programs.winapps.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable winapps.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps;
          defaultText = lib.literalExpression "inputs.winapps.packages.\${system}.winapps";
          description = "The winapps package to use. Only its bin/winapps is installed.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ launcher ];
      };
    };
}
