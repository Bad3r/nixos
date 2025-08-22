## Settings

The configuration for `grocy` is located at `/etc/grocy/config.php`. By default, the following settings can be defined in the NixOS-configuration:

```programlisting
{ pkgs, ... }:
{
  services.grocy.settings = {
    # The default currency in the system for invoices etc.

    # Please note that exchange rates aren't taken into account, this

    # is just the setting for what's shown in the frontend.

    currency = "EUR";

    # The display language (and locale configuration) for grocy.

    culture = "de";

    calendar = {
      # Whether or not to show the week-numbers

      # in the calendar.

      showWeekNumber = true;

      # Index of the first day to be shown in the calendar (0=Sunday, 1=Monday,

      # 2=Tuesday and so on).

      firstDayOfWeek = 2;
    };
  };
}
```

If you want to alter the configuration file on your own, you can do this manually with an expression like this:

```programlisting
{ lib, ... }:
{
  environment.etc."grocy/config.php".text = lib.mkAfter ''
    // Arbitrary PHP code in grocy's configuration file
  '';
}
```
