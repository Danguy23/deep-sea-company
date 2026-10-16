# AGENTS.md - Deep Sea Company

## What this project is
A cooperative underwater salvage game for Roblox in the extraction genre (Lethal
Company / R.E.P.O. lineage). Players are a salvage crew who descend from a
submarine into strange, half-flooded facilities, grab valuables, and get back to
the sub before things go wrong, banking loot against a rising quota.

## The core loop
Descend, explore, scavenge valuables, avoid the creature, haul loot back to the
submarine, bank it against the quota, then dive again into a new stage.

The one source of fun is the decision "grab one more item, or get back while I
still can?" Every system exists to sharpen that greed-versus-safety moment. If a
feature does not feed that tension or the chaos around it, it is out of scope.

## What is built (current state)
- Run state machine (RunService): Lobby -> Dive -> Return -> Payout -> next Dive
  or GameOver, with quota scaling. RunService owns the lifecycle.
- Loot (LootService): E to pick up, 4-slot inventory with size classes, 1-4 to
  select, G to drop, deposit by entering SafeZone. Large items slow you down.
  Unbanked carried loot is lost when the run ends.
- Quota (QuotaService), HUD (HP, stamina, quota, inventory), SafeZone marker.
- Movement (MovementService): grounded-floaty underwater movement with low
  gravity, momentum, sprint, and stamina.
- Threat (ThreatService): one creature that patrols, sees players by range,
  view cone, and line of sight, chases, sprints, and downs on contact.
- Downed state (DownService): all players downed ends the Dive as a failure.
- Atmosphere (AtmosphereService): neutral readable lighting baseline.
- REMOVED, do not reintroduce: oxygen/air, flashlight, light toggle, heavy
  darkness as the default.

Scene in the place file (Workspace):
- Submarine with SafeZone, 10 tagged Loot parts.
- GreyboxRuin: the original playable map. Loot and the creature currently spawn
  only inside GreyboxRuin.ThreatBounds / GreyboxRuin.Floors.
- Room_ExperimentLab_01 and Room_ServerRoom_01: the first two modular rooms.
  Built, not yet used by any code.

## Current milestone (build ONLY this)
Milestone 3: modular map scaffolding. Rooms are prebuilt templates that get
stitched together at runtime through standard doorways, Lethal Company style.
Build these steps in order, one at a time, each tested and committed separately:
1. Retrofit both existing rooms to the Room Connection Contract below.
2. RoomStitcher module: given a placed room and a template, pick an open
   connector on each and position the new room so the two connectors mate.
   No randomness, no generation yet. Test by stitching the lab to the server room
   and walking through the join.
3. Capping pass: after stitching, remove caps on mated doorways and keep caps on
   every unused doorway so there are no holes to the void.
4. Hook into RunService: build the map at Dive start and tear it down on Dive
   end. Make loot and the creature spawn inside the generated rooms instead of
   only GreyboxRuin.
Random generation, room pools, and per-stage config come after step 4. Do not
start them early.

## Room Connection Contract (every connectable room must follow this)
- Doorway opening: exactly 10 studs wide x 12 studs high, at floor level.
- Connector: each doorway has an Attachment named "Connector", parented to the
  room's PrimaryPart, centered on the opening horizontally, at floor-top height,
  on the OUTER face of the wall. Its LookVector points out of the room.
  Each Connector has a string attribute "ConnectorId", unique within the room
  (e.g. "South", "East", "Entry").
- Nothing in the room may protrude past a connector's plane except that
  doorway's cap. Two rooms mated at a connector must not overlap.
- Cap: each doorway has a Part named "Cap_<ConnectorId>", 10x12, flush against
  the outer face of the wall, anchored and collidable. Caps start solid. The
  stitcher removes the caps of mated doorways.
- Bounds: each room Model has PrimaryPart set to an anchored, invisible,
  non-collidable Part named "Bounds" that encloses the whole room. The stitcher
  uses Bounds for placement and overlap checks.
- Floors: walkable floor Parts in a room go in a Folder named "Floors" so loot and
  the creature can find spawnable ground.
- Naming: rooms are Models named Room_<Name>_<NN>.
- Free per room: wall thickness, floor thickness, ceiling height, interior layout,
  number of doorways.
- Temporary dev parts start with "TEMP_" and are ignored or removed when a room
  is used as a template.

## Room build standards
- Chase creatures are built to a swept width of 6 studs or less.
- Aisles and corridors the creature must use are at least 8 studs wide
  (6 + 2 stud drift buffer).
- Default lighting is low-light-but-readable: players see their current room and
  anything in it, not around corners or across the map. Darkness is a rare,
  deliberate per-stage setting, never the default.

## Do NOT build yet (cut list)
Random/procedural generation beyond the steps above, pressure mechanic, multiple
stages or biomes, shops, upgrades, skill trees, cosmetics, monetization, lore,
co-op netcode beyond the trivial. Do not add any of these unprompted.

## World contract (what the code may assume exists)
The 3D scene is built in Studio (by hand or via MCP), not by game logic.
Reference these by name:
- Model "Submarine" in Workspace containing Part "SafeZone". Inside SafeZone
  means "in the sub": carried loot deposits there.
- Loot: Parts tagged (CollectionService) "Loot", each with a numeric attribute
  "Value".
- GreyboxRuin with ThreatBounds and Floors (current map, until step 4 replaces it).
- Room templates following the Room Connection Contract.
If an expected instance is missing, warn loudly rather than fail silently.

## Architecture and file layout
Rojo maps files to Studio services. Put code in the right folder:
- src/server/  -> ServerScriptService (all authoritative game logic)
- src/shared/  -> ReplicatedStorage (shared modules, RemoteEvents, types, config)
- src/client/  -> StarterPlayerScripts (HUD and input only)
Naming: NAME.server.luau = server Script, NAME.client.luau = LocalScript,
NAME.luau / init.luau = ModuleScript.

Design:
- Server-authoritative. Health, carried loot, banked value, quota, and map
  generation are decided on the server. The client only displays and sends input
  intent.
- One module per system, each a ModuleScript returning a table, started from the
  single server entry script (src/server/init.server.luau).
- Server-to-client updates go through RemoteEvents defined in src/shared. The
  client never sets authoritative values.

## Code conventions
- Begin every script with --!strict and use Luau types.
- Use CollectionService tags and Instance attributes for data, not hardcoded paths.
- Local over global, small functions, clear names. Put all tunables in the Config
  ModuleScript in src/shared.
- Prefer ProximityPrompt for interactions.
- Write clean, readable code that humans can easily understand and edit.

## Change discipline (keep the codebase lean)
Prefer editing existing code over adding new code. Before writing anything new:
- Check whether a suitable module, function, or config value already exists, and
  extend or reuse it instead of creating a parallel version.
- Do not duplicate logic. Factor shared behavior into one function or module.
- Make the smallest change that fully solves the task. Do not refactor, rename, or
  reorganize unrelated code unprompted.
- Keep one responsibility per module. New functionality belongs in the system
  that owns it, unless it is genuinely a new system (RoomStitcher is one).
- Put tunable numbers in Config, never hardcoded in multiple spots.
- Only create a new file when the functionality is a distinct system. If you add
  a file, say why an existing one would not fit.

When a task could be done either by editing existing code or by adding new code,
choose the edit, and briefly note what you changed and why.

## Rojo vs MCP rule (important)
- Write all game logic as files under src/. Rojo syncs them into Studio. This is
  the versioned source of truth.
- Use the Studio MCP ONLY to read the scene, run throwaway test code, build or
  adjust the physical scene (including room retrofits), and playtest.
- Never write persistent game logic into the place via MCP. Code that lives only
  in the place is invisible to git and will be lost.
- After any scene change via MCP, remind me to save the place file (Ctrl+S) so
  the change is captured in deep-sea-company.rbxl and can be committed.

## How to verify a change
After implementing something, state how to test it: which script runs, what to
watch in the Output window on Play, and the expected values. Use server prints
during development so behavior shows in Output.

## Commit messages
After a change is implemented, output a concise commit message (imperative mood,
one line, describing what changed). Do not run it yourself; just give me the
block to paste.

## Planned direction (context only, do NOT build yet)
- Dimensional pressure replaces oxygen as the escalating danger. It is an
  extradimensional closing force, not water pressure.
- Pressure is a per-stage property set in stage config, not per player and not
  per room. One shared clock for the whole crew.
- Easy stages are calm with no pressure. Harder stages are pressure dives.
  Pressure stages recur to alternate calm and tense pacing.
- The one clock expresses differently by room and by monster: rising pressure
  agitates monsters and can open deeper areas with better loot (risk vs reward).
- Rooms only lock down or close in clearly telegraphed special rooms (boss or
  survival setpieces) with warning cues. Generic exploration rooms never close
  and never crush players by surprise.
- When the clock runs out, the surroundings crumble and crush the crew.
- Lighting is also a per-stage config field, same as pressure.

Implication for current work: keep room templates and the stitcher free of
pressure or lighting logic. Stages will pass config in later; rooms should be
able to accept per-stage settings without being rebuilt.