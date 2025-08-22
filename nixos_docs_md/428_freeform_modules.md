## Freeform modules

Freeform modules allow you to define values for option paths that have not been declared explicitly. This can be used to add attribute-specific types to what would otherwise have to be `attrsOf` options in order to accept all attribute names.

This feature can be enabled by using the attribute `freeformType` to define a freeform type. By doing this, all assignments without an associated option will be merged using the freeform type and combined into the resulting `config` set. Since this feature nullifies name checking for entire option trees, it is only recommended for use in submodules.

**Example 31. Freeform submodule**

The following shows a submodule assigning a freeform type that allows arbitrary attributes with `str` values below `settings`, but also declares an option for the `settings.port` attribute to have it type-checked and assign a default value. See [Example: Declaring a type-checked `settings` attribute](#ex-settings-typed-attrs "Example 33. Declaring a type-checked settings attribute") for a more complete example.

```programlisting
{ lib, config, ... }:
{

  options.settings = lib.mkOption {
    type = lib.types.submodule {

      freeformType = with lib.types; attrsOf str;

      # We want this attribute to be checked for the correct type

      options.port = lib.mkOption {
        type = lib.types.port;
        # Declaring the option also allows defining a default value

        default = 8080;
      };

    };
  };
}
```

And the following shows what such a module then allows

```programlisting
{
  # Not a declared option, but the freeform type allows this

  settings.logLevel = "debug";

  # Not allowed because the the freeform type only allows strings

  # settings.enable = true;

  # Allowed because there is a port option declared

  settings.port = 80;

  # Not allowed because the port option doesn't allow strings

  # settings.port = "443";

}
```

### Note

Freeform attributes cannot depend on other attributes of the same set without infinite recursion:

```programlisting
{
  # This throws infinite recursion encountered

  settings.logLevel = lib.mkIf (config.settings.port == 80) "debug";
}
```

To prevent this, declare options for all attributes that need to depend on others. For above example this means to declare `logLevel` to be an option.
