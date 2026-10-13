{
  configurations.nixos.tpnix.module = {
    programs.magnitude.extended.client.endpoint = "http://songbird.internal:10100";
  };
}
