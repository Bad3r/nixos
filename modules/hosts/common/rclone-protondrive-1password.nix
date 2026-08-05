_:
let
  body = {
    programs.rclone.extended.protonDrive.onePassword = {
      usernameRef = "op://Personal/wi7bkkt6pkphzioobyl2ddpkka/username";
      passwordRef = "op://Personal/wi7bkkt6pkphzioobyl2ddpkka/password";
      otpRef = "op://Personal/wi7bkkt6pkphzioobyl2ddpkka/one-time password";
      mailboxPasswordRef = "op://Personal/zgofe2wyj3j27vetjth7qr4hs4/password";
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
