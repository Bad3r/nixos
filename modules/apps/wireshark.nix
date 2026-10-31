/*
  Package: wireshark
  Description: Network protocol analyzer with graphical and CLI interfaces for deep packet inspection.
  Homepage: https://www.wireshark.org/
  Documentation: https://www.wireshark.org/docs/
  Repository: https://gitlab.com/wireshark/wireshark

  Summary:
    * Captures and dissects network traffic with support for hundreds of protocols and display filters.
    * Includes the `tshark` CLI and the `dumpcap` capture tool.

  Options:
    tshark -i <iface>: Perform command-line captures and parsing.
    dumpcap -i <iface> -w file.pcapng: Capture packets with minimal overhead.

  Notes:
    * Packet capture is limited to `wheel`.
*/
_:
let
  WiresharkModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.wireshark.extended;
      owner = metaOwner.username or null;
    in
    {
      options.programs.wireshark.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable wireshark.";
        };

        package = lib.mkPackageOption pkgs "wireshark" { };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            assertions = [
              {
                assertion = owner != null;
                message = "Wireshark module: expected metaOwner.username to be defined";
              }
            ];

            environment.systemPackages = [ cfg.package ];
            users.groups.wireshark = { };

            security.wrappers.dumpcap = {
              source = "${cfg.package}/bin/dumpcap";
              capabilities = "cap_net_raw,cap_net_admin+ep";
              owner = "root";
              group = "wheel";
              permissions = "u+rx,g+x";
            };
          }

          (lib.mkIf (owner != null) {
            users.users.${owner}.extraGroups = lib.mkAfter [ "wireshark" ];
          })
        ]
      );
    };
in
{
  flake.nixosModules.apps.wireshark = WiresharkModule;
}
