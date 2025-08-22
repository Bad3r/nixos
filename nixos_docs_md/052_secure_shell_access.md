## Secure Shell Access

Secure shell (SSH) access to your machine can be enabled by setting:

```programlisting
{ services.openssh.enable = true; }
```

By default, root logins using a password are disallowed. They can be disabled entirely by setting [`services.openssh.settings.PermitRootLogin`](options.html#opt-services.openssh.settings.PermitRootLogin) to `"no"`.

You can declaratively specify authorised public keys for a user as follows:

```programlisting
{
  users.users.alice.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAB3NzaC1kc3MAAACBAPIkGWVEt4..." ];
}
```
