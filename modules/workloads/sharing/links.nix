_:
let
  linksModule =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      inherit (config.workloads) networks guests sharing;
      hostServices = config.workloads.host.services;
      presentGuests = lib.filterAttrs (_: guest: guest.ensure == "present") guests;

      objectPaths = {
        guest = "workloads.guests";
        service = "workloads.services";
      };

      covers =
        port: proto: spec:
        spec.proto == proto && spec.from <= port && port <= spec.to;

      resolve =
        name: endpoint: target: interface:
        let
          match = builtins.match "([a-z]+):([a-z0-9][a-z0-9-]*)(:([1-9][0-9]{0,4})(/udp)?)?" target;
          targetKind = builtins.elemAt match 0;
          targetName = builtins.elemAt match 1;
          portText = builtins.elemAt match 3;
          port = lib.toInt portText;
          proto = if builtins.elemAt match 4 == null then "tcp" else "udp";
          explicit = [
            {
              from = port;
              to = port;
              inherit proto;
            }
          ];
          network = networks.${interface.network};
          fail = message: {
            error = "workloads.guests.${name}.links: ${target}: ${message}";
          };
          base = {
            error = null;
            inherit target targetKind targetName;
            inherit (interface) network;
            inherit (network) bridge gateway;
            source = interface.address;
          };
          peer = sharing.endpoints.${targetKind}.${targetName} or null;
          peerInterfaces = lib.filter (
            peerInterface: peerInterface.network == interface.network
          ) peer.interfaces;
          peerInterface = lib.head (if peerInterfaces != [ ] then peerInterfaces else peer.interfaces);
          peerPorts = if portText == null then peer.ports else explicit;
        in
        if lib.hasPrefix "sbx-" target then
          fail "sandboxes are runtime objects and take grants"
        else if match == null then
          fail "expected host:<service>, guest:<name>, or service:<name>, with an optional :<port>[/udp]"
        else if portText != null && port > 65535 then
          fail "ports lie between 1 and 65535"
        else if targetKind == "host" then
          let
            service = hostServices.${targetName} or null;
          in
          if service == null then
            fail "no workloads.host.services.${targetName}"
          else if endpoint.trust != "trusted" then
            fail "untrusted objects reach host services through grants only"
          else if portText != null && !lib.any (covers port proto) service.ports then
            fail "${portText}/${proto} is not among the service's ports"
          else
            base
            // {
              address = network.gateway;
              ports = if portText == null then service.ports else explicit;
              loopback = service.bind == "loopback";
            }
        else if !(objectPaths ? ${targetKind}) then
          fail "unknown kind ${targetKind}"
        else if peer == null then
          fail "no ${objectPaths.${targetKind}}.${targetName}${
            lib.optionalString (targetKind == "guest") " with ensure = \"present\""
          }"
        else if peer.interfaces == [ ] then
          fail "the target has no interface"
        else if peerPorts == [ ] then
          fail "the target declares no ports, so the link names one"
        else if peerInterface.network == interface.network && network.isolatePeers then
          fail "both sit on ${interface.network}, whose isolatePeers drops traffic between its peers"
        else
          base
          // {
            inherit (peerInterface) address;
            ports = peerPorts;
            # Same-bridge peers already reach each other.
            peerNetwork = if peerInterface.network == interface.network then null else peerInterface.network;
          };

      resolved = lib.concatLists (
        lib.mapAttrsToList (
          name: guest:
          let
            endpoint = sharing.endpoints.guest.${name};
          in
          lib.concatMap (
            target:
            if endpoint.interfaces == [ ] then
              [ { error = "workloads.guests.${name}.links: ${target}: the guest has no interface"; } ]
            else
              map (resolve name endpoint target) endpoint.interfaces
          ) guest.links
        ) presentGuests
      );

      links = lib.filter (link: link.error == null) resolved;
      hostLinks = lib.filter (link: link.targetKind == "host") links;
      peerLinks = lib.filter (link: link.targetKind != "host" && link.peerNetwork != null) links;

      portsOf = proto: ports: lib.filter (spec: spec.proto == proto) ports;
      portRange =
        spec:
        if spec.from == spec.to then toString spec.from else "${toString spec.from}-${toString spec.to}";
      nftRules =
        prefix: ports:
        lib.concatMap
          (
            proto:
            let
              specs = portsOf proto ports;
            in
            lib.optional (specs != [ ]) (prefix proto "{ ${lib.concatMapStringsSep ", " portRange specs} }")
          )
          [
            "tcp"
            "udp"
          ];

      hostRules = lib.concatMap (
        link:
        nftRules (
          proto: set:
          ''iifname "${link.bridge}" ip saddr ${link.source} ip daddr ${link.gateway} ${proto} dport ${set} accept''
        ) link.ports
      ) hostLinks;

      peerBridge = link: networks.${link.peerNetwork}.bridge;
      peerRules = lib.concatMap (
        link:
        nftRules (
          proto: set:
          ''iifname "${link.bridge}" oifname "${peerBridge link}" ip saddr ${link.source} ip daddr ${link.address} ${proto} dport ${set} ct state new accept''
        ) link.ports
      ) peerLinks;

      # Replies route back along the reverse pair.
      routedAddresses = lib.zipAttrsWith (_: lib.unique) (
        lib.concatMap (link: [
          { ${link.network} = link.address; }
          { ${link.peerNetwork} = link.source; }
        ]) peerLinks
      );

      firewallPorts =
        bridge:
        let
          ports = lib.concatMap (link: link.ports) (lib.filter (link: link.bridge == bridge) hostLinks);
          singles =
            proto:
            lib.unique (map (spec: spec.from) (lib.filter (spec: spec.from == spec.to) (portsOf proto ports)));
          ranges =
            proto:
            lib.unique (
              map (spec: { inherit (spec) from to; }) (
                lib.filter (spec: spec.from != spec.to) (portsOf proto ports)
              )
            );
        in
        {
          allowedTCPPorts = singles "tcp";
          allowedTCPPortRanges = ranges "tcp";
          allowedUDPPorts = singles "udp";
          allowedUDPPortRanges = ranges "udp";
        };

      linkTargets = lib.mapAttrs (
        _: networkLinks:
        lib.unique (
          map (link: {
            kind = link.targetKind;
            name = link.targetName;
            inherit (link) address;
          }) networkLinks
        )
      ) (lib.groupBy (link: link.network) links);

      linkProxies = lib.concatMap (
        link:
        lib.concatMap (
          spec:
          map (port: {
            inherit (link) network;
            service = link.targetName;
            inherit port;
            sources = [ link.source ];
          }) (lib.range spec.from spec.to)
        ) link.ports
      ) (lib.filter (link: link.loopback) hostLinks);

      check = assertion: message: { inherit assertion message; };

      serviceAssertions = lib.concatLists (
        lib.mapAttrsToList (
          name: service:
          let
            prefix = "workloads.host.services.${name}";
          in
          [
            (check (
              builtins.match "[a-z0-9][a-z0-9-]*" name != null
            ) "${prefix}: names must match [a-z0-9][a-z0-9-]*")
            (check (lib.all (
              spec: spec.from <= spec.to
            ) service.ports) "${prefix}.ports: `from` must not exceed `to`")
          ]
          # Each proxied port is one socket unit; dnsmasq holds 53 and 67 on the gateway.
          ++ lib.optional (service.bind == "loopback") (
            check (lib.all (
              spec: spec.proto == "tcp" && spec.from == spec.to && spec.from != 53 && spec.from != 67
            ) service.ports) "${prefix}.ports: a loopback service lists single TCP ports other than 53 and 67"
          )
        ) hostServices
      );

      guestAssertions = lib.concatLists (
        lib.mapAttrsToList (
          name: guest:
          let
            prefix = "workloads.guests.${name}";
          in
          [
            (check (lib.all (
              spec: spec.from <= spec.to
            ) guest.grantable) "${prefix}.grantable: `from` must not exceed `to`")
          ]
        ) presentGuests
      );

      proxyName = proxy: "workload-proxy-${proxy.network}-${proxy.service}-${toString proxy.port}";
      proxies = lib.mapAttrsToList (
        _: entries:
        lib.head entries
        // {
          sources = lib.unique (lib.concatMap (entry: entry.sources) entries);
        }
      ) (lib.groupBy proxyName sharing.gatewayProxies);

      proxyAssertions = lib.mapAttrsToList (
        listen: entries:
        let
          services = lib.unique (map (proxy: proxy.service) entries);
        in
        check (lib.length services == 1)
          "workloads.host.services: ${lib.concatStringsSep " and " services} are linked from one network with the same loopback port, ${listen}"
      ) (lib.groupBy (proxy: "${networks.${proxy.network}.gateway}:${toString proxy.port}") proxies);
    in
    {
      config = {
        workloads = {
          sharing = {
            endpoints = {
              guest = lib.mapAttrs (_: guest: {
                inherit (guest) trust;
                interfaces = lib.mapAttrsToList (nic: interface: {
                  inherit (interface) network;
                  address = guest.address.${nic};
                }) guest.interfaces;
                ports = guest.grantable;
              }) presentGuests;
            }
            // lib.optionalAttrs (options.workloads ? services) {
              service = lib.mapAttrs (_: service: {
                trust = "trusted";
                interfaces = [
                  {
                    inherit (service) network;
                    address = "${
                      lib.removeSuffix ".0/24" networks.${service.network}.subnet
                    }.${toString service.address}";
                  }
                ];
                ports = map (port: {
                  from = port.container;
                  to = port.container;
                  proto = port.protocol;
                }) service.ports;
              }) config.workloads.services;
            };

            inherit linkTargets;
            gatewayProxies = linkProxies;
          };

          inherit routedAddresses;
          nftables = {
            inputRules = lib.concatStringsSep "\n" hostRules;
            forwardRules = lib.concatStringsSep "\n" peerRules;
          };
        };

        assertions =
          map (link: check false link.error) (lib.filter (link: link.error != null) resolved)
          ++ serviceAssertions
          ++ guestAssertions
          ++ proxyAssertions;

        networking.firewall.interfaces = lib.genAttrs (lib.unique (
          map (link: link.bridge) hostLinks
        )) firewallPorts;

        # FreeBind lets a proxy bind its gateway before the runtime creates the bridge.
        systemd.sockets = lib.listToAttrs (
          map (
            proxy:
            lib.nameValuePair (proxyName proxy) {
              description = "Gateway proxy for host service ${proxy.service} on ${proxy.network}";
              wantedBy = [ "sockets.target" ];
              listenStreams = [ "${networks.${proxy.network}.gateway}:${toString proxy.port}" ];
              socketConfig = {
                FreeBind = true;
                # The gateway address is routable from every network.
                IPAddressDeny = "any";
                IPAddressAllow = proxy.sources;
              };
            }
          ) proxies
        );

        systemd.services = lib.listToAttrs (
          map (
            proxy:
            lib.nameValuePair (proxyName proxy) {
              description = "Gateway proxy for host service ${proxy.service} on ${proxy.network}";
              requires = [ "${proxyName proxy}.socket" ];
              after = [ "${proxyName proxy}.socket" ];
              serviceConfig = {
                ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd --exit-idle-time=10min 127.0.0.1:${toString proxy.port}";
                DynamicUser = true;
                CapabilityBoundingSet = "";
                LockPersonality = true;
                MemoryDenyWriteExecute = true;
                NoNewPrivileges = true;
                PrivateDevices = true;
                PrivateTmp = true;
                ProcSubset = "pid";
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectHostname = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectProc = "invisible";
                ProtectSystem = "strict";
                RestrictAddressFamilies = [ "AF_INET" ];
                RestrictNamespaces = true;
                RestrictRealtime = true;
                RestrictSUIDSGID = true;
                SystemCallArchitectures = "native";
                SystemCallFilter = [ "@system-service" ];
              };
            }
          ) proxies
        );
      };
    };
in
{
  flake.nixosModules."workloads-sharing" = linksModule;
}
