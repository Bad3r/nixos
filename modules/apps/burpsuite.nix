/*
  Package: burpsuite
  Description: Integrated web security testing platform from PortSwigger for intercepting, scanning, and exploiting HTTP/S traffic.
  Homepage: https://portswigger.net/
  Documentation: https://portswigger.net/burp/documentation
  Repository: https://portswigger.net/burp/releases

  Summary:
    * Provides an intercepting proxy, repeater, intruder, and extensible plugins for comprehensive web pentesting.
    * Automates vulnerability scanning while offering manual tooling for exploitation and request manipulation.

  Options:
    burpsuite: Launch the desktop suite with the default UI.
    BURP_JVM_ARGS="-Xmx4G" burpsuite: Increase JVM heap for large engagements.
    java -jar burpsuite_pro.jar: Run the packaged JAR manually for scripted environments.

  Example Usage:
    * `burpsuite` — Start Burp Suite and configure browser proxy settings to intercept traffic.
    * Install extensions from the BApp Store to expand capabilities (e.g., Autorize, Logger++).
    * Use Proxy → HTTP history to analyze captured requests before sending them to Repeater or Intruder.
*/

{
  nixpkgs.allowedUnfreePackages = [ "burpsuite" ];

  flake.nixosModules.apps.burpsuite =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.burpsuite ];
    };

}
