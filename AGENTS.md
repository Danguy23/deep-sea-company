# AGENTS.md — Deep Sea Company

## What this project is
A cooperative underwater salvage game for Roblox in the extraction genre (Lethal
Company / R.E.P.O. lineage), themed as deep-sea wreck salvage. Players are a crew
hired by a salvage company to descend into dark water, grab valuables, and get
back to the submarine before their air runs out.

## The core loop
Descend into the dark, scavenge fragile valuables, manage air (and later light and
a threat), haul loot back to the submarine, bank it against a rising quota, then
dive again, deeper.

The one source of fun is the decision "grab one more crate, or do I have enough air
to make it back?" Every system exists to sharpen that greed-versus-air moment. If a
feature does not feed that tension or the chaos around it, it is out of scope.

## Current milestone (build ONLY this)
Milestone 1: the smallest playable single-player slice. Four systems, in order:
1. Run state machine (server): Lobby -> Dive -> Return -> Payout -> next run or fail.
2. Oxygen (server-authoritative): drains while a player is outside
   the sub, refills inside it, and downs the player at zero (for our purposes in single player, the round ends).
3. Grab-and-haul loot: pick up a loot object, carry it (slower while carrying), drop it.
4. Quota and payout: banking loot inside the sub adds its Value; hitting the quota
   raises it and continues to the next stage, missing it ends the run.
Plus a minimal HUD: oxygen bar, carried value, banked value vs quota.

## Do NOT build yet (cut list)
Monsters or AI threats, a light/darkness system, co-op netcode beyond the trivial,
shops, upgrades, cosmetics, monetization, procedural maps, multiple biomes, lore.
These come after Milestone 1 is playable and fun. Do not add them unprompted.

## World contract (what the code may assume exists)
The 3D scene is built in Studio (by hand or via MCP as a one-time scaffold), not by
game logic. Reference these by name:
- A Model "Submarine" in Workspace containing a Part "SafeZone". Touching/inside
  SafeZone means "in the sub": oxygen refills and deposits count there.
- Loot: Parts tagged (CollectionService) "Loot", each with a numeric attribute
  "Value". An optional "Fragility" (0 to 1) is reserved for later; ignore it in M1.
If an expected instance is missing, warn loudly rather than fail silently.

## Architecture and file layout
Rojo maps files to Studio services. Put code in the right folder:
- src/server/  -> ServerScriptService (all authoritative game logic)
- src/shared/  -> ReplicatedStorage (shared modules, RemoteEvents, types, config)
- src/client/  -> StarterPlayerScripts (HUD and input only)
Naming: NAME.server.luau = server Script, NAME.client.luau = LocalScript,
NAME.luau / init.luau = ModuleScript.

Design:
- Server-authoritative. Oxygen, carried loot, banked value, and quota are tracked
  and enforced on the server. The client only displays and sends input intent.
- One module per system (OxygenService, LootService, QuotaService, RunService),
  each a ModuleScript returning a table, started from one server entry script.
- Server-to-client updates go through RemoteEvents defined in src/shared. The client
  never sets authoritative values.

## Code conventions
- Begin every script with --!strict and use Luau types.
- Use CollectionService tags and Instance attributes for data, not hardcoded paths.
- Local over global, small functions, clear names. Put all tunables (drain rate,
  walkspeed penalty, starting quota) in a Config ModuleScript in src/shared.
- Prefer ProximityPrompt for the pick-up interaction.
- Write clean, readable code that allows humans to easily understand and edit.

## Change discipline (keep the codebase lean)
Prefer editing existing code over adding new code. Before writing anything new:
- Check whether a suitable module, function, or config value already exists, and
  extend or reuse it instead of creating a parallel version.
- Do not duplicate logic. If the same behavior is needed in two places, factor it
  into a shared function or module rather than copying it.
- Make the smallest change that fully solves the task. Touch only what the task
  requires; do not refactor, rename, or reorganize unrelated code unprompted.
- Keep one responsibility per module. New functionality belongs in the existing
  system that owns that responsibility (e.g. oxygen logic stays in OxygenService)
  rather than in a new file, unless it is genuinely a new system.
- Put tunable numbers in the shared Config module, never hardcoded in multiple spots.
- Only create a new file when the functionality is a distinct system not covered by
  an existing one. If you do add a file, say why an existing one would not fit.

When a task could be done either by editing existing code or by adding new code,
choose the edit, and briefly note what you changed and why.

## Rojo vs MCP rule (important)
- Write all game logic as files under src/. Rojo syncs them into Studio. This is the
  versioned source of truth.
- Use the Studio MCP ONLY to read the scene, run throwaway test code, build/adjust
  the physical scene, and playtest.
- Never write persistent game logic into the place via MCP. Code that lives only in
  the place is invisible to git and will be lost.

## How to verify a change
After implementing something, state how to test it: which script runs, what to watch
in the Output window on Play, and the expected values. Use server prints during
development so behavior shows in Output.

## Commit messages
After a change is implemented output a concise commit message
(imperative mood, one line, describing what changed). Do not run it
yourself; just give me the block to paste.