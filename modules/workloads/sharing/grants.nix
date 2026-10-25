_:
let
  grantsModule =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      inherit (lib) types;
      cfg = config.workloads.grants;
      inherit (config.workloads) networks sharing;
      hostServices = config.workloads.host.services;
      guestEndpoints = sharing.endpoints.guest or { };

      # Every present guest, so a share whose declaration is gone still detaches;
      # the VM module installs each runtime share's device file.
      runtimeShares = lib.mapAttrs (name: guest: {
        domain = guest.domainName;
        inherit (guest) kind;
        shares = lib.mapAttrs (tag: share: {
          device = "/etc/workloads/shares/${name}/${tag}.xml";
          inherit (share) readOnly mountPoint;
        }) (lib.filterAttrs (_: share: share.enable && share.runtime or false) guest.shares);
      }) (lib.filterAttrs (_: guest: (guest.ensure or "present") == "present") config.workloads.guests);
      helper = cfg.allow != [ ] || lib.any (guest: guest.shares != { }) (lib.attrValues runtimeShares);

      # The bit the grant chains set on connections they admit; no other table uses ct mark.
      marked = "ct mark & 0x00f00000 == 0x00100000";
      markAccept = "${marked} accept";
      # A grant admits only the MAC whose lease named the source address.
      markGrant = "ct state new iifname . ether saddr . ip saddr @sources iifname . ip saddr . ip daddr . meta l4proto . th dport @grants ct mark set ct mark & 0xff0fffff | 0x00100000";
      # A marked connection lives only while its own element does: the
      # original tuple, not the shared mark, names the grant.
      original = "ct original ip saddr . ct original ip daddr . ct original protocol . ct original proto-dst";
      dropSent = "${marked} ct direction original iifname . ${original} != @grants drop";
      dropMoved = "${marked} ct direction original iifname . ether saddr . ip saddr != @sources drop";
      dropReplies = "${marked} ct direction reply oifname . ${original} != @grants drop";
      # A destination bridge that is gone leaves the main table's default route,
      # and `inet workload` accepts established traffic before its own checks.
      dropUplink = ''${marked} oifname != "vn-*" drop'';
      # Ahead of the workload-egress band, 31000-31999.
      routePreference = 30900;

      # Idempotent: `add` keeps the sets and their elements, `flush chain` only the rules.
      tableFile = pkgs.writeTextFile {
        name = "workload-grants.nft";
        text = ''
          add table inet workload_grants
          add set inet workload_grants grants { typeof iifname . ip saddr . ip daddr . meta l4proto . th dport; flags interval, timeout; }
          add set inet workload_grants sources { typeof iifname . ether saddr . ip saddr; flags timeout; }
          add chain inet workload_grants input { type filter hook input priority filter - 2; policy accept; }
          add chain inet workload_grants forward { type filter hook forward priority filter - 2; policy accept; }
          add chain inet workload_grants output { type filter hook output priority filter - 2; policy accept; }
          flush chain inet workload_grants input
          flush chain inet workload_grants forward
          flush chain inet workload_grants output
          add rule inet workload_grants input ${dropSent}
          add rule inet workload_grants input ${dropMoved}
          add rule inet workload_grants input ${markGrant}
          add rule inet workload_grants forward ${dropSent}
          add rule inet workload_grants forward ${dropMoved}
          add rule inet workload_grants forward ${dropReplies}
          add rule inet workload_grants forward ${markGrant}
          add rule inet workload_grants forward ${dropUplink}
          add rule inet workload_grants output ${dropReplies}
        '';
        checkPhase = ''
          LD_PRELOAD="${pkgs.buildPackages.lklWithFirewall.lib}/lib/liblkl-hijack.so" \
            ${pkgs.buildPackages.nftables}/bin/nft --check --file $out
        '';
      };
      loadTable = "${lib.getExe pkgs.nftables} -f ${tableFile}";

      units = {
        s = 1;
        m = 60;
        h = 3600;
        d = 86400;
      };
      seconds =
        text:
        let
          match = builtins.match "([1-9][0-9]*)([smhd])" text;
        in
        lib.toInt (lib.elemAt match 0) * units.${lib.elemAt match 1};

      parseTarget =
        text:
        let
          match = builtins.match "(host|guest|service):([a-z0-9][a-z0-9-]*)(:([1-9][0-9]{0,4})(/udp)?)?" text;
          portText = lib.elemAt match 3;
          port = lib.toInt portText;
        in
        if match == null || (portText != null && port > 65535) then
          null
        else
          {
            kind = lib.elemAt match 0;
            name = lib.elemAt match 1;
            port =
              if portText == null then
                null
              else
                {
                  from = port;
                  to = port;
                  proto = if lib.elemAt match 4 == null then "tcp" else "udp";
                };
          };

      sourceGuest =
        source:
        let
          match = builtins.match "guest:([a-z0-9][a-z0-9-]*)" source;
        in
        if match == null then null else lib.head match;

      covers = spec: port: spec.proto == port.proto && spec.from <= port.from && port.to <= spec.to;

      # Host services carry no interfaces; they answer at the source network's gateway.
      endpointOf =
        target:
        if target.kind == "host" then
          let
            service = hostServices.${target.name} or null;
          in
          if service == null then
            null
          else
            {
              inherit (service) ports grantable;
              interfaces = [ ];
            }
        else
          let
            endpoint = sharing.endpoints.${target.kind}.${target.name} or null;
          in
          if endpoint == null then null else endpoint // { grantable = true; };

      sandboxNetworks = lib.filterAttrs (_: network: network.libvirt.sessionAttach or false) networks;

      sources = lib.unique (lib.concatMap (rule: rule.from) cfg.allow);
      targetTexts = lib.unique (lib.concatMap (rule: rule.to) cfg.allow);
      targets = lib.filter (target: target != null && endpointOf target != null) (
        map parseTarget targetTexts
      );

      interfaceRecords = map (interface: {
        inherit (interface) network address mac;
      });
      portRecords = map (spec: {
        inherit (spec) from to proto;
      });

      policy = {
        inherit (cfg) maxConcurrent;
        inherit routePreference;
        rules = map (rule: {
          inherit (rule) from to;
          maxTtl = seconds rule.maxTtl;
        }) cfg.allow;
        networks = lib.mapAttrs (name: network: {
          inherit (network)
            bridge
            subnet
            gateway
            isolatePeers
            ;
          sandboxes = sandboxNetworks ? ${name};
          leases =
            if sandboxNetworks ? ${name} then "/var/lib/libvirt/dnsmasq/${network.bridge}.status" else null;
        }) networks;
        sources = lib.listToAttrs (
          map (name: lib.nameValuePair name (interfaceRecords guestEndpoints.${name}.interfaces)) (
            lib.filter (name: name != null && guestEndpoints ? ${name}) (map sourceGuest sources)
          )
        );
        targets = lib.foldl' lib.recursiveUpdate { } (
          map (
            target:
            let
              endpoint = endpointOf target;
            in
            {
              ${target.kind}.${target.name} = {
                ports = portRecords endpoint.ports;
                interfaces = interfaceRecords endpoint.interfaces;
              };
            }
          ) targets
        );
        # A sandbox never claims a declared object's address.
        reserved = lib.unique (
          lib.concatMap (endpoint: map (interface: interface.address) endpoint.interfaces) (
            lib.concatMap lib.attrValues (lib.attrValues sharing.endpoints)
          )
        );
        shares = runtimeShares;
        # Read by sbx, which hot-plugs sandbox shares itself.
        sandboxShares = lib.mapAttrs (_: share: { inherit (share) hostPath; }) cfg.sandboxShares;
      };

      # Where each rule's sources sit: every sandbox network's subnet, or a guest's addresses.
      sitesOf =
        source:
        if source == "sbx-*" then
          lib.mapAttrsToList (name: network: {
            network = name;
            address = network.subnet;
          }) sandboxNetworks
        else
          let
            name = sourceGuest source;
          in
          map (interface: { inherit (interface) network address; }) (
            guestEndpoints.${name}.interfaces or [ ]
          );

      grantProxies = lib.concatMap (
        rule:
        lib.concatMap (
          text:
          let
            target = parseTarget text;
            service = if target == null then null else hostServices.${target.name} or null;
          in
          if target == null || target.kind != "host" || service == null || service.bind != "loopback" then
            [ ]
          else
            lib.concatMap (
              site:
              map (port: {
                inherit (site) network;
                service = target.name;
                inherit port;
                sources = [ site.address ];
              }) (if target.port == null then map (spec: spec.from) service.ports else [ target.port.from ])
            ) (lib.concatMap sitesOf rule.from)
        ) rule.to
      ) cfg.allow;

      check = assertion: message: { inherit assertion message; };
      prefix = "workloads.grants.allow";

      sourceAssertions = map (
        source:
        check (
          source == "sbx-*" || guestEndpoints ? ${toString (sourceGuest source)}
        ) "${prefix}: from ${source}: expected sbx-* or guest:<name> of a present guest"
      ) sources;

      sandboxRules = lib.any (rule: lib.elem "sbx-*" rule.from) cfg.allow;

      # Grants match a sandbox by its leased address and MAC, which only lease binding pins to it.
      leaseAssertions = lib.optionals sandboxRules (
        lib.mapAttrsToList (
          name: network:
          check (network.libvirt.bindLeases or false
          ) "${prefix}: sbx-* sources sit on workloads.networks.${name}, which needs libvirt.bindLeases"
        ) sandboxNetworks
      );

      macAssertions = map (
        source:
        let
          name = sourceGuest source;
        in
        check (lib.all (interface: interface.mac != null) (
          guestEndpoints.${name}.interfaces or [ ]
        )) "${prefix}: from ${source}: the guest has an interface without a MAC"
      ) (lib.filter (source: sourceGuest source != null) sources);

      targetAssertion =
        text:
        let
          target = parseTarget text;
          endpoint = endpointOf target;
          fail = message: check false "${prefix}: to ${text}: ${message}";
        in
        if target == null then
          fail "expected host:<service>, guest:<name>, or service:<name>, with an optional :<port>[/udp]"
        else if endpoint == null then
          fail "no such ${if target.kind == "host" then "workloads.host.services" else target.kind} entry"
        else if !endpoint.grantable then
          fail "the host service is not grantable"
        else if endpoint.ports == [ ] then
          fail "the target declares no grantable ports"
        else if target.port != null && !lib.any (spec: covers spec target.port) endpoint.ports then
          fail "the port is not among the target's grantable ports"
        else
          check true "";

      # A tag is QEMU's virtiofs tag inside the sandbox; shared is the sandbox's own.
      sandboxShareAssertions = lib.mapAttrsToList (
        tag: _:
        check (tag != "shared" && builtins.match "[a-z0-9][a-z0-9-]{0,35}" tag != null)
          "workloads.grants.sandboxShares.${tag}: tags must match [a-z0-9][a-z0-9-]*, have at most 36 characters, and not be shared"
      ) cfg.sandboxShares;
    in
    {
      options.workloads.grants = {
        allow = lib.mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                from = lib.mkOption {
                  type = types.nonEmptyListOf types.str;
                  example = [
                    "sbx-*"
                    "guest:nixos-dev"
                  ];
                  description = "Sources: `sbx-*` for every sandbox, or `guest:<name>` for a declared guest.";
                };

                to = lib.mkOption {
                  type = types.nonEmptyListOf types.str;
                  example = [
                    "host:llm"
                    "guest:nixos-dev:8080"
                  ];
                  description = ''
                    Targets, in the link grammar. A host service must be
                    `grantable`; a guest or container service opens its
                    `grantable` or declared ports. A port narrows the entry to
                    that port.
                  '';
                };

                maxTtl = lib.mkOption {
                  type = types.strMatching "[1-9][0-9]*[smhd]";
                  default = "2h";
                  description = "Longest lifetime a grant under this rule may request.";
                };
              };
            }
          );
          default = [ ];
          description = ''
            Runtime grants the `workloads grant` command may open without a
            prompt. A grant matches the ingress bridge, the source's MAC and
            address, the destination, the protocol, and the ports. It permits
            all traffic on that path only until its TTL ends: at expiry or
            revoke, every connection it admitted stops, and no other grant's.
            Declaring a rule, or a guest share with `runtime = true`, starts
            `workload-grantd`.
          '';
        };

        sandboxShares = lib.mkOption {
          type = types.attrsOf (
            types.submodule {
              options.hostPath = lib.mkOption {
                type = types.strMatching "/.*";
                description = ''
                  Host directory to share. `sbx` refuses one that is or holds
                  $HOME or the sbx state directory, after resolving links.
                '';
              };
            }
          );
          default = { };
          example.docs.hostPath = "/srv/docs";
          description = ''
            Directories `workloads share attach sbx-<name> <tag>` hot-plugs
            into a running sandbox, always read-only, keyed by their virtiofs
            tag. A sandbox's own `shared` directory is its only read-write share.
          '';
        };

        maxConcurrent = lib.mkOption {
          type = types.ints.positive;
          default = 8;
          description = "Live grants one source may hold.";
        };
      };

      config = lib.mkMerge [
        # The table and the routes outlive the service, so dropping the last
        # rule removes them instead of leaving marks no chain honours.
        (lib.mkIf (!helper && networks != { }) {
          systemd.services.workload-grants = {
            description = "Remove the workload grant table and routes";
            wantedBy = [ "multi-user.target" ];
            after = [ "nftables.service" ];
            path = [
              pkgs.iproute2
              pkgs.nftables
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              nft destroy table inet workload_grants
              while ip rule show pref ${toString routePreference} | grep -q .; do
                ip rule del pref ${toString routePreference}
              done
            '';
          };
        })

        (lib.mkIf (helper || cfg.sandboxShares != { }) {
          assertions = sandboxShareAssertions;

          programs.workloads.extended.enable = lib.mkOverride 1050 true;

          environment.etc."workloads/grants.json".text = builtins.toJSON policy;
        })

        (lib.mkIf helper {
          assertions =
            sourceAssertions ++ leaseAssertions ++ macAssertions ++ map targetAssertion targetTexts;

          workloads.sharing.gatewayProxies = grantProxies;
          workloads.nftables = {
            inputRules = markAccept;
            forwardRules = markAccept;
            serviceTables = [ "inet workload_grants" ];
          };
          # A drop in any base chain is final, so nixos-fw accepts granted ports too.
          networking.firewall.extraInputRules = markAccept;

          systemd = {
            services.workload-grants = {
              # Outside networking.nftables.tables, whose reloads delete and
              # recreate each table and would empty the set.
              description = "Netfilter table for workload grants";
              wantedBy = [ "multi-user.target" ];
              requires = [ "nftables.service" ];
              after = [ "nftables.service" ];
              # A reload restores the chains after a flushed ruleset.
              unitConfig.ReloadPropagatedFrom = [ "nftables.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = loadTable;
                ExecReload = loadTable;
              };
            };

            sockets.workload-grantd = {
              description = "Workload grant helper socket";
              wantedBy = [ "sockets.target" ];
              listenStreams = [ "/run/workloads/grant.sock" ];
              socketConfig = {
                Accept = true;
                SocketUser = metaOwner.username;
                SocketMode = "0600";
                DirectoryMode = "0755";
                MaxConnections = 16;
              };
            };

            services."workload-grantd@" = {
              description = "Workload grant helper";
              wants = [ "workload-grants.service" ];
              after = [ "workload-grants.service" ];
              serviceConfig = {
                ExecStart = "${config.programs.workloads.extended.package}/bin/workload-grantd";
                StandardInput = "socket";
                StandardOutput = "socket";
                StandardError = "journal";
                SyslogIdentifier = "workload-grant";
                RuntimeMaxSec = 60;
                # libvirtd admits a uid 0 client without polkit, so share verbs need no capability.
                CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
                ReadWritePaths = [ "/run/workloads" ];
                UMask = "0077";
                IPAddressDeny = "any";
                LockPersonality = true;
                MemoryDenyWriteExecute = true;
                NoNewPrivileges = true;
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectHostname = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectSystem = "strict";
                RestrictAddressFamilies = [
                  "AF_UNIX"
                  "AF_NETLINK"
                ];
                RestrictNamespaces = true;
                RestrictRealtime = true;
                RestrictSUIDSGID = true;
                SystemCallArchitectures = "native";
                SystemCallFilter = [ "@system-service" ];
              };
            };
          };
        })
      ];
    };
in
{
  flake.nixosModules."workloads-sharing" = grantsModule;
}
