{
  flake.nixosModules.hosts-common.imports = [
    (
      { hostName, ... }:
      {
        networking.hostName = hostName;
      }
    )
  ];
}
