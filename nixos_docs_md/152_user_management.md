## User management

After the GoToSocial service is running, the `gotosocial-admin` utility can be used to manage users. In particular an administrative user can be created with

```programlisting
$ sudo gotosocial-admin account create --username <nickname> --email <email> --password <password>
$ sudo gotosocial-admin account confirm --username <nickname>
$ sudo gotosocial-admin account promote --username <nickname>
```
