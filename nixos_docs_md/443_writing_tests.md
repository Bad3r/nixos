## Writing Tests

A NixOS test is a module that has the following structure:

```programlisting
{

  # One or more machines:

  nodes = {
    machine =
      { config, pkgs, ... }:
      {
        # ...

      };
    machine2 =
      { config, pkgs, ... }:
      {
        # ...

      };
    # …

  };

  testScript = ''
    Python code…
  '';
}
```

We refer to the whole test above as a test module, whereas the values in [`nodes.<name>`](#test-opt-nodes) are NixOS modules themselves.

The option [`testScript`](#test-opt-testScript) is a piece of Python code that executes the test (described below). During the test, it will start one or more virtual machines, the configuration of which is described by the option [`nodes`](#test-opt-nodes).

An example of a single-node test is [`login.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/login.nix). It only needs a single machine to test whether users can log in on the virtual console, whether device ownership is correctly maintained when switching between consoles, and so on. An interesting multi-node test is [`nfs/simple.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/nfs/simple.nix). It uses two client nodes to test correct locking across server crashes.

### Calling a test

Tests are invoked differently depending on whether the test is part of NixOS or lives in a different project.

#### Testing within NixOS

Tests that are part of NixOS are added to [`nixos/tests/all-tests.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/all-tests.nix).

```programlisting
{ hostname = runTest ./hostname.nix; }
```

Overrides can be added by defining an anonymous module in `all-tests.nix`.

```programlisting
{
  hostname = runTest {
    imports = [ ./hostname.nix ];
    defaults.networking.firewall.enable = false;
  };
}
```

You can run a test with attribute name `hostname` in `nixos/tests/all-tests.nix` by invoking:

```programlisting
cd /my/git/clone/of/nixpkgs
nix-build -A nixosTests.hostname
```

#### Testing outside the NixOS project

Outside the `nixpkgs` repository, you can use the `runNixOSTest` function from `pkgs.testers`:

```programlisting
let
  pkgs = import <nixpkgs> { };

in
pkgs.testers.runNixOSTest {
  imports = [ ./test.nix ];
  defaults.services.foo.package = mypkg;
}
```

`runNixOSTest` returns a derivation that runs the test.

### Configuring the nodes

There are a few special NixOS options for test VMs:

`virtualisation.memorySize`
The memory of the VM in MiB (1024×1024 bytes).

`virtualisation.vlans`
The virtual networks to which the VM is connected. See [`nat.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/nat.nix) for an example.

`virtualisation.writableStore`
By default, the Nix store in the VM is not writable. If you enable this option, a writable union file system is mounted on top of the Nix store to make it appear writable. This is necessary for tests that run Nix operations that modify the store.

For more options, see the module [`qemu-vm.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/qemu-vm.nix).

The test script is a sequence of Python statements that perform various actions, such as starting VMs, executing commands in the VMs, and so on. Each virtual machine is represented as an object stored in the variable `name` if this is also the identifier of the machine in the declarative config. If you specified a node `nodes.machine`, the following example starts the machine, waits until it has finished booting, then executes a command and checks that the output is more-or-less correct:

```programlisting
machine.start()
machine.wait_for_unit("default.target")
t.assertIn("Linux", machine.succeed("uname"), "Wrong OS")
```

The first line is technically unnecessary; machines are implicitly started when you first execute an action on them (such as `wait_for_unit` or `succeed`). If you have multiple machines, you can speed up the test by starting them in parallel:

```programlisting
start_all()
```

Under the variable `t`, all assertions from [`unittest.TestCase`](https://docs.python.org/3/library/unittest.html) are available.

If the hostname of a node contains characters that can’t be used in a Python variable name, those characters will be replaced with underscores in the variable name, so `nodes.machine-a` will be exposed to Python as `machine_a`.

### Machine objects

The following methods are available on machine objects:

\_managed_screenshot()
Take a screenshot and yield the screenshot filepath. The file will be deleted when leaving the generator.

block()
Simulate unplugging the Ethernet cable that connects the machine to the other machines. This happens by shutting down eth1 (the multicast interface used to talk to the other VMs). eth0 is kept online to still enable the test driver to communicate with the machine.

console_interact()
Allows you to directly interact with QEMU’s stdin, by forwarding terminal input to the QEMU process. This is for use with the interactive test driver, not for production tests, which run unattended. Output from QEMU is only read line-wise. `Ctrl-c` kills QEMU and `Ctrl-d` closes console and returns to the test runner.

copy_from_host(source, target)
Copies a file from host to machine, e.g., `copy_from_host("myfile", "/etc/my/important/file")`.

The first argument is the file on the host. Note that the “host” refers to the environment in which the test driver runs, which is typically the Nix build sandbox.

The second argument is the location of the file on the machine that will be written to.

The file is copied via the `shared_dir` directory which is shared among all the VMs (using a temporary directory). The access rights bits will mimic the ones from the host file and user:group will be root:root.

copy_from_host_via_shell(source, target)
Copy a file from the host into the guest by piping it over the shell into the destination file. Works without host-guest shared folder. Prefer copy_from_host for whenever possible.

copy_from_vm(source, target_dir)
Copy a file from the VM (specified by an in-VM source path) to a path relative to `$out`. The file is copied via the `shared_dir` shared among all the VMs (using a temporary directory).

crash()
Simulate a sudden power failure, by telling the VM to exit immediately.

dump_tty_contents(tty)
Debugging: Dump the contents of the TTY\<n\>

execute(command, check_return, check_output, timeout)
Execute a shell command, returning a list `(status, stdout)`.

Commands are run with `set -euo pipefail` set:

- If several commands are separated by `;` and one fails, the command as a whole will fail.

- For pipelines, the last non-zero exit status will be returned (if there is one; otherwise zero will be returned).

- Dereferencing unset variables fails the command.

- It will wait for stdout to be closed.

If the command detaches, it must close stdout, as `execute` will wait for this to consume all output reliably. This can be achieved by redirecting stdout to stderr `>&2`, to `/dev/console`, `/dev/null` or a file. Examples of detaching commands are `sleep 365d &`, where the shell forks a new process that can write to stdout and `xclip -i`, where the `xclip` command itself forks without closing stdout.

Takes an optional parameter `check_return` that defaults to `True`. Setting this parameter to `False` will not check for the return code and return -1 instead. This can be used for commands that shut down the VM and would therefore break the pipe that would be used for retrieving the return code.

A timeout for the command can be specified (in seconds) using the optional `timeout` parameter, e.g., `execute(cmd, timeout=10)` or `execute(cmd, timeout=None)`. The default is 900 seconds.

fail()
Like `succeed`, but raising an exception if the command returns a zero status.

forward_port(host_port, guest_port)
Forward a TCP port on the host to a TCP port on the guest. Useful during interactive testing.

get_screen_text()
Return a textual representation of what is currently visible on the machine’s screen using optical character recognition.

### Note

This requires [`enableOCR`](#test-opt-enableOCR) to be set to `true`.

get_screen_text_variants()
Return a list of different interpretations of what is currently visible on the machine’s screen using optical character recognition. The number and order of the interpretations is not specified and is subject to change, but if no exception is raised at least one will be returned.

### Note

This requires [`enableOCR`](#test-opt-enableOCR) to be set to `true`.

reboot()
Press Ctrl+Alt+Delete in the guest.

Prepares the machine to be reconnected which is useful if the machine was started with `allow_reboot = True`

screenshot(filename)
Take a picture of the display of the virtual machine, in PNG format. The screenshot will be available in the derivation output.

send_chars(chars, delay)
Simulate typing a sequence of characters on the virtual keyboard, e.g., `send_chars("foobar\n")` will type the string `foobar` followed by the Enter key.

send_console(chars)
Send keys to the kernel console. This allows interaction with the systemd emergency mode, for example. Takes a string that is sent, e.g., `send_console("\n\nsystemctl default\n")`.

send_key(key, delay, log)
Simulate pressing keys on the virtual keyboard, e.g., `send_key("ctrl-alt-delete")`.

Please also refer to the QEMU documentation for more information on the input syntax: https://en.wikibooks.org/wiki/QEMU/Monitor#sendkey_keys

send_monitor_command(command)
Send a command to the QEMU monitor. This allows attaching virtual USB disks to a running machine, among other things.

shell_interact(address)
Allows you to directly interact with the guest shell. This should only be used during test development, not in production tests. Killing the interactive session with `Ctrl-d` or `Ctrl-c` also ends the guest session.

shutdown()
Shut down the machine, waiting for the VM to exit.

start(allow_reboot)
Start the virtual machine. This method is asynchronous — it does not wait for the machine to finish booting.

succeed()
Execute a shell command, raising an exception if the exit status is not zero, otherwise returning the standard output. Similar to `execute`, except that the timeout is `None` by default. See `execute` for details on command execution.

switch_root()
Transition from stage 1 to stage 2. This requires the machine to be configured with `testing.initrdBackdoor = true` and `boot.initrd.systemd.enable = true`.

systemctl(q, user)
Runs `systemctl` commands with optional support for `systemctl --user`

```programlisting

# run `systemctl list-jobs --no-pager`

machine.systemctl("list-jobs --no-pager")

# spawn a shell for `any-user` and run

# `systemctl --user list-jobs --no-pager`

machine.systemctl("list-jobs --no-pager", "any-user")
```

unblock()
Undo the effect of `block`.

wait_for_closed_port(port, addr, timeout)
Wait until nobody is listening on the given TCP port and IP address (default `localhost`).

wait_for_console_text(regex, timeout)
Wait until the supplied regular expressions match a line of the serial console output. This method is useful when OCR is not possible or inaccurate.

wait_for_file(filename, timeout)
Waits until the file exists in the machine’s file system.

wait_for_open_port(port, addr, timeout)
Wait until a process is listening on the given TCP port and IP address (default `localhost`).

wait_for_open_unix_socket(addr, is_datagram, timeout)
Wait until a process is listening on the given UNIX-domain socket (default to a UNIX-domain stream socket).

wait_for_qmp_event(event_filter, timeout)
Wait for a QMP event which you can filter with the `event_filter` function. The function takes as an input a dictionary of the event and if it returns True, we return that event, if it does not, we wait for the next event and retry.

It will skip all events received in the meantime, if you want to keep them, you have to do the bookkeeping yourself and store them somewhere.

By default, it will wait up to 10 minutes, `timeout` is in seconds.

wait_for_text(regex, timeout)
Wait until the supplied regular expressions matches the textual contents of the screen by using optical character recognition (see `get_screen_text` and `get_screen_text_variants`).

### Note

This requires [`enableOCR`](#test-opt-enableOCR) to be set to `true`.

wait_for_unit(unit, user, timeout)
Wait for a systemd unit to get into “active” state. Throws exceptions on “failed” and “inactive” states as well as after timing out.

wait_for_window(regexp, timeout)
Wait until an X11 window has appeared whose name matches the given regular expression, e.g., `wait_for_window("Terminal")`.

wait_for_x(timeout)
Wait until it is possible to connect to the X server.

wait_until_fails(command, timeout)
Like `wait_until_succeeds`, but repeating the command until it fails.

wait_until_succeeds(command, timeout)
Repeat a shell command with 1-second intervals until it succeeds. Has a default timeout of 900 seconds which can be modified, e.g. `wait_until_succeeds(cmd, timeout=10)`. See `execute` for details on command execution. Throws an exception on timeout.

wait_until_tty_matches(tty, regexp, timeout)
Wait until the visible output on the chosen TTY matches regular expression. Throws an exception on timeout.

To test user units declared by `systemd.user.services` the optional `user` argument can be used:

```programlisting
machine.start()
machine.wait_for_x()
machine.wait_for_unit("xautolock.service", "x-session-user")
```

This applies to `systemctl`, `get_unit_info`, `wait_for_unit`, `start_job` and `stop_job`.

For faster dev cycles it’s also possible to disable the code-linters (this shouldn’t be committed though):

```programlisting
{
  skipLint = true;
  nodes.machine =
    { config, pkgs, ... }:
    {
      # configuration…

    };

  testScript = ''
    Python code…
  '';
}
```

This will produce a Nix warning at evaluation time. To fully disable the linter, wrap the test script in comment directives to disable the Black linter directly (again, don’t commit this within the Nixpkgs repository):

```programlisting
{
  testScript = ''
    # fmt: off

    Python code…
    # fmt: on

  '';
}
```

Similarly, the type checking of test scripts can be disabled in the following way:

```programlisting
{
  skipTypeCheck = true;
  nodes.machine =
    { config, pkgs, ... }:
    {
      # configuration…

    };
}
```

### Failing tests early

To fail tests early when certain invariants are no longer met (instead of waiting for the build to time out), the decorator `polling_condition` is provided. For example, if we are testing a program `foo` that should not quit after being started, we might write the following:

```programlisting
@polling_condition
def foo_running():
    machine.succeed("pgrep -x foo")

machine.succeed("foo --start")
machine.wait_until_succeeds("pgrep -x foo")

with foo_running:
    ...  # Put `foo` through its paces

```

`polling_condition` takes the following (optional) arguments:

`seconds_interval`
specifies how often the condition should be polled:

```programlisting
@polling_condition(seconds_interval=10)
def foo_running():
    machine.succeed("pgrep -x foo")
```

`description`
is used in the log when the condition is checked. If this is not provided, the description is pulled from the docstring of the function. These two are therefore equivalent:

```programlisting
@polling_condition
def foo_running():
    "check that foo is running"
    machine.succeed("pgrep -x foo")
```

```programlisting
@polling_condition(description="check that foo is running")
def foo_running():
    machine.succeed("pgrep -x foo")
```

### Adding Python packages to the test script

When additional Python libraries are required in the test script, they can be added using the parameter `extraPythonPackages`. For example, you could add `numpy` like this:

```programlisting
{
  extraPythonPackages = p: [ p.numpy ];

  nodes = { };

  # Type checking on extra packages doesn't work yet

  skipTypeCheck = true;

  testScript = ''
    import numpy as np
    assert str(np.zeros(4)) == "[0. 0. 0. 0.]"
  '';
}
```

In that case, `numpy` is chosen from the generic `python3Packages`.

### Overriding a test

The NixOS test framework returns tests with multiple overriding methods.

`overrideTestDerivation` _function_
Like applying `overrideAttrs` on the [test](#test-opt-test) derivation.

This is a convenience for `extend` with an override on the [`rawTestDerivationArg`](#test-opt-rawTestDerivationArg) option.

_function_
An extension function, e.g. `finalAttrs: prevAttrs: { /* … */ }`, the result of which is passed to [`mkDerivation`](https://nixos.org/manual/nixpkgs/stable/#sec-using-stdenv). Just as with `overrideAttrs`, an abbreviated form can be used, e.g. `prevAttrs: { /* … */ }` or even `{ /* … */ }`. See [`lib.extends`](https://nixos.org/manual/nixpkgs/stable/#function-library-lib.fixedPoints.extends).

`extendNixOS { module = ` _module_ `; specialArgs = ` _specialArgs_ `; }`
Evaluates the test with additional NixOS modules and/or arguments.

`module`
A NixOS module to add to all the nodes in the test. Sets test option [`extraBaseModules`](#test-opt-extraBaseModules).

`specialArgs`
An attribute set of arguments to pass to all NixOS modules. These override the existing arguments, as well as any `_module.args.<name>` that the modules may define. Sets test option [`node.specialArgs`](#test-opt-node.specialArgs).

This is a convenience function for `extend` that overrides the aforementioned test options.

**Example 34. Using extendNixOS in `passthru.tests` to make `(openssh.tests.overrideAttrs f).tests.nixos` coherent**

```programlisting
mkDerivation (finalAttrs: {
  # …

  passthru = {
    tests = {
      nixos = nixosTests.openssh.extendNixOS {
        module = {
          services.openssh.package = finalAttrs.finalPackage;
        };
      };
    };
  };
})
```

`extend { modules = ` _modules_ `; specialArgs = ` _specialArgs_ `; }`
Adds new `nixosTest` modules and/or module arguments to the test, which are evaluated together with the existing modules and [built-in options](#sec-test-options-reference "Test Options Reference").

If you’re only looking to extend the _NixOS_ configurations of the test, and not something else about the test, you may use the `extendNixOS` convenience function instead.

`modules`
A list of modules to add to the test. These are added to the existing modules and then [evaluated](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules) together.

`specialArgs`
An attribute of arguments to pass to the test. These override the existing arguments, as well as any `_module.args.<name>` that the modules may define. See [`evalModules`/`specialArgs`](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules-param-specialArgs).

### Test Options Reference

The following options can be used when writing tests.

[`enableDebugHook`](#test-opt-enableDebugHook)
Halt test execution after any test fail and provide the possibility to hook into the sandbox to connect with either the test driver via `telnet localhost 4444` or with the VMs via SSH and vsocks (see also `sshBackdoor.enable`).

_Type:_ boolean

_Default:_ `false`

_Example:_ `true`

_Declared by:_

|                                                                                                             |
| ----------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/run.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/run.nix)` ` |

[`enableOCR`](#test-opt-enableOCR)
Whether to enable Optical Character Recognition functionality for testing graphical programs. See [`Machine objects`](#ssec-machine-objects "Machine objects").

_Type:_ boolean

_Default:_ `false`

_Declared by:_

|                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/driver.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/driver.nix)` ` |

[`defaults`](#test-opt-defaults)
NixOS configuration that is applied to all [`nodes`](#test-opt-nodes).

_Type:_ module

_Default:_ `{ }`

_Declared by:_

|                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/nodes.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/nodes.nix)` ` |

[`driver`](#test-opt-driver)
Package containing a script that runs the test.

_Type:_ package

_Default:_ set by the test framework

_Declared by:_

|                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/driver.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/driver.nix)` ` |

[`extraBaseModules`](#test-opt-extraBaseModules)
NixOS configuration that, like [`defaults`](#test-opt-defaults), is applied to all [`nodes`](#test-opt-nodes) and can not be undone with [`specialisation.<name>.inheritParentConfig`](https://search.nixos.org/options?show=specialisation.%3Cname%3E.inheritParentConfig&from=0&size=50&sort=relevance&type=packages&query=specialisation).

_Type:_ module

_Default:_ `{ }`

_Declared by:_

|                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/nodes.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/nodes.nix)` ` |

[`extraDriverArgs`](#test-opt-extraDriverArgs)
Extra arguments to pass to the test driver.

They become part of [`driver`](#test-opt-driver) via `wrapProgram`.

_Type:_ list of string

_Default:_ `[ ]`

_Declared by:_

|                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/driver.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/driver.nix)` ` |

[`extraPythonPackages`](#test-opt-extraPythonPackages)
Python packages to add to the test driver.

The argument is a Python package set, similar to `pkgs.pythonPackages`.

_Type:_ function that evaluates to a(n) list of package

_Default:_ `<function>`

_Example:_

```programlisting
p: [ p.numpy ]
```

_Declared by:_

|                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/driver.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/driver.nix)` ` |

[`globalTimeout`](#test-opt-globalTimeout)
A global timeout for the complete test, expressed in seconds. Beyond that timeout, every resource will be killed and released and the test will fail.

By default, we use a 1 hour timeout.

_Type:_ signed integer

_Default:_ `3600`

_Example:_ `600`

_Declared by:_

|                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/driver.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/driver.nix)` ` |

[`hostPkgs`](#test-opt-hostPkgs)
Nixpkgs attrset used outside the nodes.

_Type:_ raw value

_Example:_

```programlisting
import nixpkgs { inherit system config overlays; }
```

_Declared by:_

|                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/driver.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/driver.nix)` ` |

[`interactive`](#test-opt-interactive)
Tests [can be run interactively](#sec-running-nixos-tests-interactively "Running Tests interactively") using the program in the test derivation’s `.driverInteractive` attribute.

When they are, the configuration will include anything set in this submodule.

You can set any top-level test option here.

Example test module:

```programlisting
{ config, lib, ... }: {

  nodes.rabbitmq = {
    services.rabbitmq.enable = true;
  };

  # When running interactively ...

  interactive.nodes.rabbitmq = {
    # ... enable the web ui.

    services.rabbitmq.managementPlugin.enable = true;
  };
}
```

For details, see the section about [running tests interactively](#sec-running-nixos-tests-interactively "Running Tests interactively").

_Type:_ submodule

_Declared by:_

|                                                                                                                             |
| --------------------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/interactive.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/interactive.nix)` ` |

[`meta`](#test-opt-meta)
The [`meta`](https://nixos.org/manual/nixpkgs/stable/#chap-meta) attributes that will be set on the returned derivations.

Not all [`meta`](https://nixos.org/manual/nixpkgs/stable/#chap-meta) attributes are supported, but more can be added as desired.

_Type:_ submodule

_Default:_ `{ }`

_Declared by:_

|                                                                                                               |
| ------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/meta.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/meta.nix)` ` |

[`meta.broken`](#test-opt-meta.broken)
Sets the [`meta.broken`](https://nixos.org/manual/nixpkgs/stable/#var-meta-broken) attribute on the [`test`](#test-opt-test) derivation.

_Type:_ boolean

_Default:_ `false`

_Declared by:_

|                                                                                                               |
| ------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/meta.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/meta.nix)` ` |

[`meta.hydraPlatforms`](#test-opt-meta.hydraPlatforms)
Sets the [`meta.hydraPlatforms`](https://nixos.org/manual/nixpkgs/stable/#var-meta-hydraPlatforms) attribute on the [`test`](#test-opt-test) derivation.

_Type:_ list of raw value

_Default:_ `lib.platforms.linux` only, as the `hydra.nixos.org` build farm does not currently support virtualisation on Darwin.

_Declared by:_

|                                                                                                               |
| ------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/meta.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/meta.nix)` ` |

[`meta.maintainers`](#test-opt-meta.maintainers)
The [list of maintainers](https://nixos.org/manual/nixpkgs/stable/#var-meta-maintainers) for this test.

_Type:_ list of raw value

_Default:_ `[ ]`

_Declared by:_

|                                                                                                               |
| ------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/meta.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/meta.nix)` ` |

[`meta.platforms`](#test-opt-meta.platforms)
Sets the [`meta.platforms`](https://nixos.org/manual/nixpkgs/stable/#var-meta-platforms) attribute on the [`test`](#test-opt-test) derivation.

_Type:_ list of raw value

_Default:_

```programlisting
[
  "aarch64-linux"
  "armv5tel-linux"
  "armv6l-linux"
  "armv7a-linux"
  "armv7l-linux"
  "i686-linux"
  "loongarch64-linux"
  "m68k-linux"
  "microblaze-linux"
  "microblazeel-linux"
  "mips-linux"
  "mips64-linux"
  "mips64el-linux"
  "mipsel-linux"
  "powerpc64-linux"
  "powerpc64le-linux"
  "riscv32-linux"
  "riscv64-linux"
  "s390-linux"
  "s390x-linux"
  "x86_64-linux"
  "x86_64-darwin"
  "aarch64-darwin"
]
```

_Declared by:_

|                                                                                                               |
| ------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/meta.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/meta.nix)` ` |

[`meta.timeout`](#test-opt-meta.timeout)
The [`test`](#test-opt-test)’s [`meta.timeout`](https://nixos.org/manual/nixpkgs/stable/#var-meta-timeout) in seconds.

_Type:_ null or signed integer

_Default:_ `3600`

_Declared by:_

|                                                                                                               |
| ------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/meta.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/meta.nix)` ` |

[`name`](#test-opt-name)
The name of the test.

This is used in the derivation names of the [`driver`](#test-opt-driver) and [`test`](#test-opt-test) runner.

_Type:_ string

_Declared by:_

|                                                                                                               |
| ------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/name.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/name.nix)` ` |

[`node.pkgs`](#test-opt-node.pkgs)
The Nixpkgs to use for the nodes.

Setting this will make the `nixpkgs.*` options read-only, to avoid mistakenly testing with a Nixpkgs configuration that diverges from regular use.

_Type:_ null or Nixpkgs package set

_Default:_ `null`, so construct `pkgs` according to the `nixpkgs.*` options as usual.

_Declared by:_

|                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/nodes.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/nodes.nix)` ` |

[`node.pkgsReadOnly`](#test-opt-node.pkgsReadOnly)
Whether to make the `nixpkgs.*` options read-only. This is only relevant when [`node.pkgs`](#test-opt-node.pkgs) is set.

Set this to `false` when any of the [`nodes`](#test-opt-nodes) needs to configure any of the `nixpkgs.*` options. This will slow down evaluation of your test a bit.

_Type:_ boolean

_Default:_ `node.pkgs != null`

_Declared by:_

|                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/nodes.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/nodes.nix)` ` |

[`node.specialArgs`](#test-opt-node.specialArgs)
An attribute set of arbitrary values that will be made available as module arguments during the resolution of module `imports`.

Note that it is not possible to override these from within the NixOS configurations. If you argument is not relevant to `imports`, consider setting `defaults._module.args.<name>` instead.

_Type:_ lazy attribute set of raw value

_Default:_ `{ }`

_Declared by:_

|                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/nodes.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/nodes.nix)` ` |

[`nodes`](#test-opt-nodes)
An attribute set of NixOS configuration modules.

The configurations are augmented by the [`defaults`](#test-opt-defaults) option.

They are assigned network addresses according to the `nixos/lib/testing/network.nix` module.

A few special options are available, that aren’t in a plain NixOS configuration. See [Configuring the nodes](#sec-nixos-test-nodes "Configuring the nodes")

_Type:_ lazy attribute set of module

_Declared by:_

|                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/nodes.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/nodes.nix)` ` |

[`passthru`](#test-opt-passthru)
Attributes to add to the returned derivations, which are not necessarily part of the build.

This is a bit like doing `drv // { myAttr = true; }` (which would be lost by `overrideAttrs`). It does not change the actual derivation, but adds the attribute nonetheless, so that consumers of what would be `drv` have more information.

_Type:_ lazy attribute set of raw value

_Declared by:_

|                                                                                                             |
| ----------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/run.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/run.nix)` ` |

[`qemu.package`](#test-opt-qemu.package)
Which qemu package to use for the virtualisation of [`nodes`](#test-opt-nodes).

_Type:_ package

_Default:_ `"hostPkgs.qemu_test"`

_Declared by:_

|                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/driver.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/driver.nix)` ` |

[`rawTestDerivationArg`](#test-opt-rawTestDerivationArg)
Argument passed to `mkDerivation` to create the `rawTestDerivation`.

_Type:_ function that evaluates to a(n) raw value

_Declared by:_

|                                                                                                             |
| ----------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/run.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/run.nix)` ` |

[`skipLint`](#test-opt-skipLint)
Do not run the linters. This may speed up your iteration cycle, but it is not something you should commit.

_Type:_ boolean

_Default:_ `false`

_Declared by:_

|                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/driver.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/driver.nix)` ` |

[`skipTypeCheck`](#test-opt-skipTypeCheck)
Disable type checking. This must not be enabled for new NixOS tests.

This may speed up your iteration cycle, unless you’re working on the [`testScript`](#test-opt-testScript).

_Type:_ boolean

_Default:_ `false`

_Declared by:_

|                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/driver.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/driver.nix)` ` |

[`sshBackdoor.enable`](#test-opt-sshBackdoor.enable)
Whether to turn on the VSOCK-based access to all VMs. This provides an unauthenticated access intended for debugging.

_Type:_ boolean

_Default:_ `config.enableDebugHook`

_Declared by:_

|                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/nodes.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/nodes.nix)` ` |

[`sshBackdoor.vsockOffset`](#test-opt-sshBackdoor.vsockOffset)
This field is only relevant when multiple users run the (interactive) driver outside the sandbox and with the SSH backdoor activated. The typical symptom for this being a problem are error messages like this: `vhost-vsock: unable to set guest cid: Address already in use`

This option allows to assign an offset to each vsock number to resolve this.

This is a 32bit number. The lowest possible vsock number is `3` (i.e. with the lowest node number being `1`, this is 2+1).

_Type:_ integer between 2 and 4294967296 (both inclusive)

_Default:_ `2`

_Declared by:_

|                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/nodes.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/nodes.nix)` ` |

[`test`](#test-opt-test)
Derivation that runs the test as its “build” process.

This implies that NixOS tests run isolated from the network, making them more dependable.

_Type:_ package

_Declared by:_

|                                                                                                             |
| ----------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/run.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/run.nix)` ` |

[`testScript`](#test-opt-testScript)
A series of python declarations and statements that you write to perform the test.

_Type:_ string or function that evaluates to a(n) string

_Declared by:_

|                                                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------- |
| ` `[`nixos/lib/testing/testScript.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/testing/testScript.nix)` ` |

### Accessing VMs in the sandbox with SSH

### Note

For debugging with SSH access into the machines, it’s recommended to try using [the interactive driver](#sec-running-nixos-tests-interactively "Running Tests interactively") with its [SSH backdoor](#sec-nixos-test-ssh-access "SSH Access for test machines") first.

This feature is mostly intended to debug flaky test failures that aren’t reproducible elsewhere.

As explained in [the section called “SSH Access for test machines”](#sec-nixos-test-ssh-access "SSH Access for test machines"), it’s possible to configure an SSH backdoor based on AF_VSOCK. This can be used to SSH into a VM of a running build in a sandbox.

This can be done when something in the test fails, e.g.

```programlisting
{
  nodes.machine = { };

  sshBackdoor.enable = true;
  enableDebugHook = true;

  testScript = ''
    start_all()
    machine.succeed("false") # this will fail

  '';
}
```

For the AF_VSOCK feature to work, `/dev/vhost-vsock` is needed in the sandbox which can be done with e.g.

```programlisting
nix-build -A nixosTests.foo --option sandbox-paths /dev/vhost-vsock
```

This will halt the test execution on a test-failure and print instructions on how to enter the sandbox shell of the VM test. Inside, one can log into e.g. `machine` with

```programlisting
ssh -F ./ssh_config vsock/3
```

As described in [the section called “SSH Access for test machines”](#sec-nixos-test-ssh-access "SSH Access for test machines"), the numbers for vsock start at `3` instead of `1`. So the first VM in the network (sorted alphabetically) can be accessed with `vsock/3`.

Alternatively, it’s possible to explicitly set a breakpoint with `debug.breakpoint()`. This also has the benefit, that one can step through `testScript` with `pdb` like this:

```programlisting
$ sudo /nix/store/eeeee-attach <id>
bash# telnet 127.0.0.1 4444

pdb$ …
```
