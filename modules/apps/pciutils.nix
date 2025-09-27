/*
  Package: pciutils
  Description: Utilities for listing and configuring PCI devices.
  Homepage: https://mj.ucw.cz/sw/pciutils/
  Documentation: https://mj.ucw.cz/sw/pciutils/pciutils.html
  Repository: https://git.kernel.org/pub/scm/utils/pciutils/pciutils.git

  Summary:
    * Includes `lspci`, `setpci`, and related tools for inspecting PCI bus hardware and drivers.
    * Resolves vendor and device names using the pci.ids database for troubleshooting and inventory.

  Options:
    -vv: Show verbose capability details in `lspci -vv` output.
    -k: Display kernel driver bindings and modules in use via `lspci -k`.
    -s <device>: Target specific devices when adjusting registers with `setpci -s <device> <cap>=<value>`.
*/

/*
  Package: pciutils
  Description: Utilities for listing and configuring PCI devices.
  Homepage: https://mj.ucw.cz/sw/pciutils/
  Documentation: https://mj.ucw.cz/sw/pciutils/pciutils.html
  Repository: https://git.kernel.org/pub/scm/utils/pciutils/pciutils.git

  Summary:
    * Includes `lspci`, `setpci`, and related tools for inspecting PCI bus hardware and drivers.
    * Resolves vendor and device names using the pci.ids database for troubleshooting and inventory.

  Options:
    lspci -vv: Show verbose capability details for PCI devices.
    lspci -k: Display kernel driver bindings and modules in use.
    setpci -s <device> <cap>=<value>: Adjust PCI configuration registers.
*/

{
  flake.nixosModules.apps.pciutils =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pciutils ];
    };
}
