{ lib, ... }:
{
  configurations.nixos.system76.module = {
    # Tor Configuration - Client Only Mode
    # =======================================
    # This configuration ensures Tor runs ONLY as a client and will NEVER act as:
    # - Exit relay (no exit traffic to internet)
    # - Middle relay (no relay traffic)
    # - Bridge (no bridge functionality)
    # - Directory authority
    #
    # References:
    # - NixOS Tor module: nixpkgs/nixos/modules/services/security/tor.nix
    # - Tor documentation: https://www.torproject.org/docs/documentation.html
    # - Architecture: Client -> Guard -> Middle -> Exit -> Destination
    services.tor = {
      enable = true;

      # Client-only mode configuration
      # When client.enable = true and relay.enable is false (default),
      # the NixOS module automatically prevents relay functionality by:
      # - Setting ORPort = [] (no relay port)
      # - Setting PublishServerDescriptor = false
      client.enable = true;

      # Explicitly ensure relay functionality is disabled
      # This is the default, but we set it explicitly for clarity
      relay.enable = false;

      # SOCKS proxy configuration for client applications
      # IsolateDestAddr = true provides better privacy by creating
      # separate circuits for different destination addresses
      client.socksListenAddress = {
        addr = "127.0.0.1";
        port = 9050;
        IsolateDestAddr = true;
      };

      settings = {
        # Override default ExitPolicy which interferes with client onion service access
        # The NixOS module defaults to "reject *:*" which is only needed for relays
        # For clients, this should not be set as it can block onion service resolution
        ExitPolicy = lib.mkForce [ ];

        # Note: Do NOT override SOCKSPort here - let the client.socksListenAddress
        # setting from the NixOS module configure it properly

        # DNS port for Tor DNS resolution
        # Prevents DNS leaks by routing DNS queries through Tor
        DNSPort = [
          {
            addr = "127.0.0.1";
            port = 9053;
          }
        ];

        # Control port with cookie authentication
        # Used by tools like nyx for monitoring
        # CookieAuthentication is more secure than password auth
        ControlPort = [
          {
            addr = "127.0.0.1";
            port = 9051;
          }
        ];
        CookieAuthentication = true;

        # Prevent publishing server descriptor (already default with relay.enable = false)
        PublishServerDescriptor = false;

        # Note: ExitPolicy is automatically set when relay.enable = false
        # Explicitly setting it might interfere with onion service resolution

        # Privacy and security settings
        SafeLogging = true; # Don't log sensitive information

        # Use entry guards for better security and performance
        # This is the default, but documented for clarity
        UseEntryGuards = true;

        # Number of entry guards (default is 3, which is good for most users)
        NumEntryGuards = 3;

        # Circuit build timeout (default 60s)
        # Lower values may cause more failed circuits, higher may be slower
        # CircuitBuildTimeout = 60;

        # Limit connection padding to reduce bandwidth usage
        # (useful for metered connections, but reduces some privacy)
        # ConnectionPadding = "auto";
      };
    };
  };
}
