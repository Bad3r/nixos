## Upgrade from 2022.3 to 2023.x

Starting with YouTrack 2023.1, JetBrains no longer distributes it as as JAR. The new distribution with the JetBrains Launcher as a ZIP changed the basic data structure and also some configuration parameters. Check out https://www.jetbrains.com/help/youtrack/server/YouTrack-Java-Start-Parameters.html for more information on the new configuration options. When upgrading to YouTrack 2023.1 or higher, a migration script will move the old state directory to `/var/lib/youtrack/2022_3` as a backup. A one-time manual update is required:

1.  Before you update take a backup of your YouTrack instance!

2.  Migrate the options you set in `services.youtrack.extraParams` and `services.youtrack.jvmOpts` to `services.youtrack.generalParameters` and `services.youtrack.environmentalParameters` (see the examples and [the YouTrack docs](https://www.jetbrains.com/help/youtrack/server/2023.3/YouTrack-Java-Start-Parameters.html))

3.  To start the upgrade set `services.youtrack.package = pkgs.youtrack`

4.  YouTrack then starts in upgrade mode, meaning you need to obtain the wizard token as above

5.  Select you want to **Upgrade** YouTrack

6.  As source you select `/var/lib/youtrack/2022_3/teamsysdata/` (adopt if you have a different state path)

7.  Change the data directory location to `/var/lib/youtrack/data/`. The other paths should already be right.

If you migrate a larger YouTrack instance, it might be useful to set `-Dexodus.entityStore.refactoring.forceAll=true` in `services.youtrack.generalParameters` for the first startup of YouTrack 2023.x.
