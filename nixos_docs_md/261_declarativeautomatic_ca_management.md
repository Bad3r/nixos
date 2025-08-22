## Declarative/automatic CA management

Everything is done according to what you specify in the module options, however in order to set up a Taskwarrior 2 client for synchronisation with a Taskserver instance, you have to transfer the keys and certificates to the client machine.

This is done using **nixos-taskserver user export \$orgname \$username** which is printing a shell script fragment to stdout which can either be used verbatim or adjusted to import the user on the client machine.

For example, let’s say you have the following configuration:

```programlisting
{
  services.taskserver.enable = true;
  services.taskserver.fqdn = "server";
  services.taskserver.listenHost = "::";
  services.taskserver.organisations.my-company.users = [ "alice" ];
}
```

This creates an organisation called `my-company` with the user `alice`.

Now in order to import the `alice` user to another machine `alicebox`, all we need to do is something like this:

```programlisting
$ ssh server nixos-taskserver user export my-company alice | sh
```

Of course, if no SSH daemon is available on the server you can also copy & paste it directly into a shell.

After this step the user should be set up and you can start synchronising your tasks for the first time with **task sync init** on `alicebox`.

Subsequent synchronisation requests merely require the command **task sync** after that stage.
