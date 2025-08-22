## Configuring clients to use this server

### Firefox desktop

To configure a desktop version of Firefox to use your server, navigate to `about:config` in your Firefox profile and set `identity.sync.tokenserver.uri` to `https://myhostname:5000/1.0/sync/1.5`.

### Firefox Android

To configure an Android version of Firefox to use your server:

- First ensure that you are disconnected from you Mozilla account.

- Go to App Menu \> Settings \> About Firefox and click the logo 5 times. You should see a “debug menu enabled” notification.

- Back to the main menu, a new menu “sync debug” should have appeared.

- In this menu, set “custom sync server” to `https://myhostname:5000/1.0/sync/1.5`.

### Warning

Changes to this configuration value are ignored if you are currently connected to your account.

- Restart the application.

- Log in to your account.
