## User Management

**Table of Contents**

[Create users and groups with `systemd-sysusers`](#sec-systemd-sysusers)

[Manage users and groups with `userborn`](#sec-userborn)

NixOS supports both declarative and imperative styles of user management. In the declarative style, users are specified in `configuration.nix`. For instance, the following states that a user account named `alice` shall exist:

```programlisting
{
  users.users.alice = {
    isNormalUser = true;
    home = "/home/alice";
    description = "Alice Foobar";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = [ "ssh-dss AAAAB3Nza... alice@foobar" ];
  };
}
```

Note that `alice` is a member of the `wheel` and `networkmanager` groups, which allows her to use `sudo` to execute commands as `root` and to configure the network, respectively. Also note the SSH public key that allows remote logins with the corresponding private key. Users created in this way do not have a password by default, so they cannot log in via mechanisms that require a password. However, you can use the `passwd` program to set a password, which is retained across invocations of `nixos-rebuild`.

If you set [`users.mutableUsers`](options.html#opt-users.mutableUsers) to false, then the contents of `/etc/passwd` and `/etc/group` will be congruent to your NixOS configuration. For instance, if you remove a user from [`users.users`](options.html#opt-users.users) and run nixos-rebuild, the user account will cease to exist. Also, imperative commands for managing users and groups, such as useradd, are no longer available. Passwords may still be assigned by setting the user’s [hashedPassword](options.html#opt-users.users._name_.hashedPassword) option. A hashed password can be generated using `mkpasswd`.

A user ID (uid) is assigned automatically. You can also specify a uid manually by adding

```programlisting
{ uid = 1000; }
```

to the user specification.

Groups can be specified similarly. The following states that a group named `students` shall exist:

```programlisting
{ users.groups.students.gid = 1000; }
```

As with users, the group ID (gid) is optional and will be assigned automatically if it’s missing.

In the imperative style, users and groups are managed by commands such as `useradd`, `groupmod` and so on. For instance, to create a user account named `alice`:

```programlisting

# useradd -m alice

```

To make all nix tools available to this new user use \`su - USER\` which opens a login shell (==shell that loads the profile) for given user. This will create the ~/.nix-defexpr symlink. So run:

```programlisting

# su - alice -c "true"

```

The flag `-m` causes the creation of a home directory for the new user, which is generally what you want. The user does not have an initial password and therefore cannot log in. A password can be set using the `passwd` utility:

```programlisting

# passwd alice

Enter new UNIX password: ***
Retype new UNIX password: ***
```

A user can be deleted using `userdel`:

```programlisting

# userdel -r alice

```

The flag `-r` deletes the user’s home directory. Accounts can be modified using `usermod`. Unix groups can be managed using `groupadd`, `groupmod` and `groupdel`.
