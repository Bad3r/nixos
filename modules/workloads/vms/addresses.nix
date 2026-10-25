_:
let
  addressesModule =
    { config, lib, ... }:
    let
      networks = lib.filterAttrs (_: network: network.libvirt.enable) config.workloads.networks;
      presentGuests = lib.filterAttrs (_: guest: guest.ensure == "present") config.workloads.guests;

      nics = lib.concatLists (
        lib.mapAttrsToList (
          _: guest:
          lib.mapAttrsToList (nic: interface: {
            inherit (interface) network;
            tap = guest.tap.${nic};
            mac = guest.mac.${nic};
            address = guest.address.${nic};
          }) guest.interfaces
        ) presentGuests
      );

      set = values: "{ ${lib.concatStringsSep ", " values} }";

      # A pinned tap speaks only for its own MAC and address.
      nicRules = nic: [
        ''iifname "${nic.tap}" ether saddr != ${nic.mac} drop''
        ''iifname "${nic.tap}" ip saddr 0.0.0.0 udp sport 68 udp dport 67 accept''
        ''iifname "${nic.tap}" ip saddr != ${nic.address} drop''
        ''iifname "${nic.tap}" arp saddr ether != ${nic.mac} drop''
        ''iifname "${nic.tap}" arp saddr ip != { ${nic.address}, 0.0.0.0 } drop''
      ];

      # No other port of the bridge may claim the gateway or a declared MAC or
      # address, whether or not its owner is running.
      networkRules =
        name: network:
        let
          dev = ''meta ibrname "${network.bridge}"'';
          owned = lib.filter (nic: nic.network == name) nics;
          taps = set (map (nic: ''"${nic.tap}"'') owned);
          addresses = set (map (nic: nic.address) owned);
          macs = set (map (nic: nic.mac) owned);
        in
        [
          "${dev} ip saddr ${network.gateway} drop"
          "${dev} arp saddr ip ${network.gateway} drop"
        ]
        ++ lib.optionals (owned != [ ]) [
          # Keeps the bridge from learning a pinned MAC on another port.
          "${dev} iifname != ${taps} ether saddr ${macs} drop"
          "${dev} iifname != ${taps} ip saddr ${addresses} drop"
          "${dev} iifname != ${taps} arp saddr ip ${addresses} drop"
        ];
    in
    {
      networking.nftables.tables.workload-addresses = {
        enable = networks != { };
        family = "bridge";
        content = ''
          chain prerouting {
            type filter hook prerouting priority filter; policy accept;
            ${lib.concatStringsSep "\n" (lib.concatMap nicRules nics)}
            ${lib.concatStringsSep "\n" (lib.concatLists (lib.mapAttrsToList networkRules networks))}
          }
        '';
      };
    };
in
{
  flake.nixosModules."workloads-vms" = addressesModule;
}
