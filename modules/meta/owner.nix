
{ lib, ... }:
{
  # Define all metadata used throughout the configuration
  config.flake.meta = {
    # Owner information
    owner = {
      username = "vx";
      email = "bad3r@unsigned.sh";
      name = "Bad3r";
      matrix = "@bad3r:matrix.org";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj4fDeDKrAatG6IW5aEgA4ym8l+hj/r7Upeos11Gqu5 bad3r@unsigned.sh"
      ];
    };
    
    # System configuration
    system = {
      timezone = "Asia/Riyadh";
      locale = "en_US.UTF-8";
      stateVersion = "25.05";
      hostName = "system76";  # Can be overridden per host
    };
    
    # Package versions - centralized version management
    packages = {
      nodejs = "nodejs_22";
      python = "python312";
      postgresql = "postgresql_16";
      rust = "rustc";
      go = "go";
    };
    
    # Feature flags
    features = {
      gaming = false;
      virtualization = true;
      development = true;
      security = true;
    };
    
    # Network configuration
    network = {
      sshPort = 6234;
      enableAvahi = false;  # Can be overridden for printing
    };
  };
}