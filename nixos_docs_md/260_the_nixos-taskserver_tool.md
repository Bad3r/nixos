## The nixos-taskserver tool

Because Taskserver by default only provides scripts to setup users imperatively, the **nixos-taskserver** tool is used for addition and deletion of organisations along with users and groups defined by [`services.taskserver.organisations`](options.html#opt-services.taskserver.organisations) and as well for imperative set up.

The tool is designed to not interfere if the command is used to manually set up some organisations, users or groups.

For example if you add a new organisation using **nixos-taskserver org add foo**, the organisation is not modified and deleted no matter what you define in `services.taskserver.organisations`, even if you’re adding the same organisation in that option.

The tool is modelled to imitate the official **taskd** command, documentation for each subcommand can be shown by using the `--help` switch.
