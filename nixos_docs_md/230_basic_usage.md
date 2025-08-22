## Basic Usage

A minimal configuration looks like this:

```programlisting
{
  services.atalkd = {
    enable = true;
    interfaces.wlan0.config = ''-router -phase 2 -net 1 -addr 1.48 -zone "Default"'';
  };
}
```

It is also valid to use atalkd without setting `services.netatalk.interfaces` to any value, only providing `services.atalkd.enable = true`. In this case it will inherit the behavior of the upstream application when an empty config file is found, which is to listen on and use all interfaces.
