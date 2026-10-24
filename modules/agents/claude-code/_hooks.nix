# settings.json hooks, compiled from the shared registry (modules/agents/hooks.nix).
# Declaring the key here replaces any hook added through /hooks on the next
# activation.
{ agents, pkgs }:
{
  hooks = agents.hooks.clients.claude pkgs;
}
