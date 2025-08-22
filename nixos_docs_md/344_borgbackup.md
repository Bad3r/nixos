## BorgBackup

**Table of Contents**

[Configuring](#module-services-backup-borgbackup-configuring)

[Basic usage for a local backup](#opt-services-backup-borgbackup-local-directory)

[Create a borg backup server](#opt-services-backup-create-server)

[Backup to the borg repository server](#opt-services-backup-borgbackup-remote-server)

[Backup to a hosting service](#opt-services-backup-borgbackup-borgbase)

[Vorta backup client for the desktop](#opt-services-backup-borgbackup-vorta)

_Source:_ `modules/services/backup/borgbackup.nix`

_Upstream documentation:_ [https://borgbackup.readthedocs.io/](https://borgbackup.readthedocs.io/)

[BorgBackup](https://www.borgbackup.org/) (short: Borg) is a deduplicating backup program. Optionally, it supports compression and authenticated encryption.

The main goal of Borg is to provide an efficient and secure way to backup data. The data deduplication technique used makes Borg suitable for daily backups since only changes are stored. The authenticated encryption technique makes it suitable for backups to not fully trusted targets.
