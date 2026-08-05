_:
let
  # mkOverride 1100 matches the hosts-common baseline priority used by
  # apps-enable.nix, so a per-host file can point these at another vault at
  # 1000 the way modules/tpnix/apps-enable.nix does. At default priority a
  # per-host definition would either lose (1000) or conflict (100), leaving
  # mkForce as the only escape hatch.
  body =
    { lib, ... }:
    {
      programs.rclone.extended.protonDrive.onePassword = {
        usernameRef = lib.mkOverride 1100 "op://Personal/wi7bkkt6pkphzioobyl2ddpkka/username";
        passwordRef = lib.mkOverride 1100 "op://Personal/wi7bkkt6pkphzioobyl2ddpkka/password";
        otpRef = lib.mkOverride 1100 "op://Personal/wi7bkkt6pkphzioobyl2ddpkka/one-time password";
        mailboxPasswordRef = lib.mkOverride 1100 "op://Personal/zgofe2wyj3j27vetjth7qr4hs4/password";
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
