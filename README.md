# Aetherpunk Fleet

Godot 4.7 / GDScript / Compatibility renderer. Double-click `LaunchGame.bat` to play using the installed local Godot executable, or open `project.godot` and press **F5**.

The prototype includes a main menu, battle, victory/defeat summaries, and a live content editor. **Start Game** opens fleet preparation using saved content. **Retry Battle** replays the fleet you launched; editor playtests use the editor's saved setup. Results and running battles keep detached snapshots.

## Playing

Empty formation and magic-circle slots are frameless at rest. Relevant action selection or drag targeting reveals destination frames; cancelling clears them. Cover remains visible on vacant slots.

Drag a card from the shared hand into an empty magic-circle slot. Click highlighted ships for targets, circle cards for circle targets, or a visible reaction/stance for control effects. Click other hand cards and/or temporary mana crystals to pay. The action resolves automatically as soon as all required targets and costs are complete. **Cancel Play** refunds the pending card, payment, crystals, and resource reservations while it is still incomplete. For optional boosts, select the hand card and use **Boosts** before placing/paying for it.

The mana cost is locked on placement. Excess payment is lost. Main effects and allied chains finish before payment cards are discarded in click order and their discard abilities resolve. Newly exposed discard-top passives affect subsequent plays. After those chains finish, each represented enemy may react once, in formation order. Replacement stance cards cannot react to the action revealing them, including a one-card deck that replaces itself.

The hand groups cards by ship in fleet-roster order, then Attack, Guard, Manoeuvre, Support; names sort within each group. Hover cards, ships, circle slots, and enemy-row cards for complete generated rules. Hover a ship for its unique resource gain/spend rules and optional boost. Rules name the owning ship, refer to a triggering card's ship as "that card's owner", and omit routine default targets. Green **BONUS** marks adjacent contributors; animated links show chained effects. Units have larger, borderless art and health numbers inside their bars. Shields appear only when positive; armour and weapon details appear in icon-rich tooltips alongside each ship’s personal-resource mechanic. Target/drag/reaction highlights appear only while relevant. Stance cards show reaction conditions and enemy-phase activity. Hovering one highlights its owner and affected ships, with a detached preview against current defences. The draw pile uses the generated card back; the discard pile shows its actual top card. Both show live counts, with pending payment shown separately. Hand cards glow red while choosing payment cards or satisfying an effect discard. Click the discard pile to inspect full cards in order, newest/top first; scroll horizontally to see older cards.

Selecting or hovering a hand card highlights the exact visible enemy reactions it would provoke, allied circle/hand/discard cards whose rules would fire, and ships with triggered mechanisms. Hovering a different circle slot, payment card, or pending target updates the prediction; dragging onto a basic repair/swap/move previews that action instead. End Fleet Phase hover shows turn-end triggers. Cues clear when leaving/cancelling. Unpaid or incomplete choices are provisional; predictions use only known payment cards and detached combat state, without consuming battle RNG or revealing hidden replacements/draws. Trigger tooltips include the generated rule text.

Each hit has a generic aether projectile, trail and impact sparks, including enemy reactions and multi-hit attacks. Blocked hits impact the cloud or shield plane. Moving ships follow slight opposing arcs when swapping, with input locked until feedback completes. Cyan force fields appear in front of shielded units and travel with them. Pale cover clouds belong to their formation slots, including empty slots. Both respond to absorption and disappear when depleted or expired. These procedural effects never change combat state.


Cards use ship-coloured borders, a coloured type icon at top left, mana cost at top right, and purple crystals for discard production. Shared vector keyword icons replace rules terms across combat, previews, preparation, feedback, and editor labels. Hover an icon for its name and definition; tooltips and editable source fields retain readable text.

### Fleet and preparation

Each of the three ships has a weapon, armour, and a named resource. Resources start at zero, persist between rounds, and reset on defeat. The initial capacity is six, before authored bonuses. Optional boosts reserve their resource before automatic spending rules evaluate.

Choose your fleet in **Main Menu → Start Game → Fleet Preparation**, then **Launch Battle**. **Fleet Setup** shows the formation and draggable ship/captain rosters. Drag ships to move or swap positions, including empty positions; their assigned captain and upgrades travel with them. Drag captain badges or roster captains onto ships to assign/swap them. Available entries use fixed-width frames; assigned ships and captains appear only in the formation. Captain frames show a portrait, name and tier, with their own round **i** button for details. Ship information buttons use the same simple round design. Drag a fleet ship or captain onto its row’s **Unassign** slot to bench it; unassigning a ship also frees its captain. Drag an available ship into an empty position and then assign a captain. Launch is disabled until all three ships and captains are assigned. Roster ships can replace an occupied ship. **Compare Airships** and **Compare Captains** sit beside the corresponding drag sources and show full stats, cards and mechanics, with selection/assignment controls.

Click a ship's **i** button to open its details, captain, level and branch options, effective stats, rules and complete contributed card row. Assignment and position dropdowns have been removed. Level-3 options respect the block imposed by level 2. **Compare Level 2/3 branches** opens the branch cards, special rules and passives side by side; selecting an upgrade raises the ship's level if needed. Level 3 requires a level-2 choice first. **Fleet Deck** remains a separate tab showing the assembled fleet deck by ship and primary type, combining repeated designs with accurate copy counts. Preparation changes update both previews immediately.

Each ship supplies two copies of each of **two distinct starter designs**: one has a single effect and the other has two effects. Its captain supplies two additional cards. Levels 2 and 3 each add an upgrade pair, giving **6 / 8 / 10 physical cards per ship**, including its captain. Level-2 card designs have two effects and level-3 designs three. Captain cards have one effect per tier; tier is an authored power budget, not a statistics multiplier. Each level-2 branch blocks one level-3 package, leaving the shared third option available on either path. The editor supplies defaults and the encounter. Older imported definitions without `starter_two` retain their original single starter pair until edited; new ships and all shipped ships have both designs.

Preparation choices stay in the current session and never write content files. **Back**, marked with an arrow, remembers your draft (including incomplete assignments); **Reset to Saved Fleet** restores authored defaults. If the saved fixed opening includes unavailable cards after your changes, launch uses a shuffled seven-card hand. Preparation hides encounter details and opening-hand implementation labels; the footer shows only ship and card counts. **Retry Battle** resets the exact prepared snapshot; **Prepare Fleet** on normal result screens returns to selection. Editor playtests continue to use saved editor setup. Changed saved content resets stale preparation choices.

Initial provisional balance:

| Ship | Hull | Armour | Weapon | Resource |
| --- | ---: | ---: | --- | --- |
| Bastion | 28 | 2 | 4, Short | Resolve: mitigation and protection |
| Kestrel | 20 | 0 | 5, Long | Momentum: movement and attacks |
| Lamplighter | 18 | 1 | 3, Long | Aether: actual repair and support |

The shipped encounter starts at level 2 with Iona, Rook, and Voss, a 24-card fleet deck, and a fixed seven-card opening. Stormmaw contributes six stance cards, Storm Ray three, and Needlewing two. All balance values are editable.

### Formation, attacks, and basic actions

Both sides use Front, Upper Middle, Lower Middle, and Rear diamond positions. Short attacks cannot originate from Rear or target Rear. Movement earlier in an action changes the legal origin. Enemy attacks choose their matching position, except Rear attacks Front; otherwise they choose the first legal occupied position in Front, Upper, Lower, Rear order.

Each attack locks one target. Hits stop when it dies. Each hit resolves **slot cover → armour → shields → hull**. Armour reduces every hit without being consumed. Generic attack bonuses apply to the first hit; per-hit bonuses are separate chunks. Damage-threshold reactions use actual hull loss. Enemy-phase attacks retain escalation: +1 damage per round after round 3.

Drag a ship's own card onto it for a basic repair, onto an adjacent living ally to swap, or onto an adjacent empty position to move. These actions resolve immediately on drop and discard the card without paying its printed mana cost or running its On Play rules. There is no separate manoeuvre or confirmation button. Repair restores 2 hull. A defeated ship accumulates recovery and revives with 4 hull when it reaches 4 recovery, occupying its former position if free, otherwise the first empty position. Recovery and movement have appropriate highlights and tooltips. The basic discard and actual repair/revival/movement can trigger authored rules.

### Magic circle, persistence, and rounds

The first four circle slots form a cycle. Filling all four expands it to nine spaces after the allied action. Centre touches all four original spaces; each new corner touches two. Original links remain. Positions never compact.

Played cards stay active through the enemy phase. At player-turn cleanup, a card starting with persistence loses one token and stays, including when it reaches zero. A card starting cleanup with zero tokens is discarded without On Discard abilities. Retained cards keep their exact positions and adjacency; they do not replay On Play. Expansion lasts until the circle is entirely empty.

At **End Fleet Phase**, holding at least two cards earns one temporary mana crystal at the next player turn, subject to capacity (normally one). Unspent crystals expire when ending the fleet phase. Click crystals during pending payment; they provide one mana and cannot satisfy discard effects. Generation and capacity can be modified by rules.

The three visible enemy cards activate left to right, discarding and replacing each afterward. Multiple cards can activate one enemy repeatedly. Replacements add no activations to that phase. Each surviving enemy that had no activation performs its weaker default action afterward. Defeated enemies' cards leave the shared row and pool.

After enemy actions, shields and cover expire, persistence cleanup runs, turn limits reset, and earned mana is granted. The hand automatically refills to seven while retaining unspent cards. Cards can only be discarded for an action cost or an authored effect. Right-click and refill do not offer voluntary discards. Committed payment, basic-action costs, and effect discards can trigger discard abilities. Win after defeating all enemies while a ship survives; lose when the fleet is destroyed. Results report surviving ships, remaining hull, and rounds.

### Control and hidden information

**Stun** suppresses one selected visible reaction until fleet-phase end; enemy activity continues. **Confuse** discards and replaces one selected row card. **Scry** reveals up to X available deck cards, takes Y into hand, and lets you order the rest back on top or discard them. Mandatory discard and scry suspend the committed queue. Revealed decisions must be completed; Cancel Play cannot undo hidden information.

Previews run the same registered effects on detached state. They show known public effects and mark uncertainty, without consuming live RNG or revealing draw/replacement identities.

## Content editor and rules

**Editor** has searchable Enemies, Ships, Captains, and Cards tabs with New, Duplicate, and Delete. Stable IDs survive renames. Referenced entries cannot be deleted until their loadouts, ownership, or setup references change.

The right panel contains shared in-game previews and Battle Setup. Configure fleet order, captains, levels, legal branches, one to four enemy instances, fixed/random opening hand, mana defaults, and basic-action values. Each enemy contributes editable stance designs with copy counts and has a separate weaker default action.

Rules are reusable **code-defined chunks** in `scripts/rules/rule_registry.gd`. Data contains IDs and parameters, never executable scripts. The registry owns typed schemas, validation, editor fields, generated text, and handlers. The generic rule editor combines triggers, boolean conditions, optional resource costs, ordered effects, and passive modifiers. See [docs/RULE_CHUNKS.md](docs/RULE_CHUNKS.md) for authoring and execution details.

**Save All** validates and writes `data/content.json`. It creates no Git commit. **Revert Unsaved Changes** restores saved content. **Save & Test Battle** saves first, then launches a battle with Return to Editor in its menu and results. Leaving a dirty draft offers Save, Discard, or Cancel. Failed validation/writes preserve the previous save.

Content version 3 includes progression, captains, composable rules, and the shared enemy deck. Versions 1 and 2 migrate in memory without rewriting files until Save. IDs, imported decks, and supported effects are retained. Imported cards are explicitly flagged if they do not meet the new 1–3-block convention; migration does not invent abilities. The immutable `gdd_content.json`, `diamond_content.json`, and `fleet_content.json` fixtures isolate regressions from live design edits.

## Verification

With the Godot console executable on PATH:

```powershell
godot --headless --path . --editor --import --quit
./tests/run_tests.ps1 -Godot godot
```

Tests cover registry metadata/forms/execution, immutable migrations and failed saves, physical pair assembly and branches, resources and boosts, payment cancellation, mana, persistence, armour/multi-hit/range, enemy ownership/replacements/defaults, control effects, hidden decisions, native drag/drop, animated feedback, results/retries, and editor playtests. UI checks use a 1280 × 800 viewport; editor and battle content scroll in smaller windows.

Campaign progression, XP, acquisition, production art, and custom content scripts remain outside this prototype.


### Generated art

The game loads the generated painterly art from `assets/generated/`: three ship rigs, three creature rigs, three captain portraits, card and button skins, a two-layer sky, and both luminous magic-circle stages. Ship balloons and creature limbs use parented attachment pivots and subtle idle rotations; suspension cables follow their two moving endpoints. A shared visual clock preserves idle poses across UI refreshes and never uses combat RNG. The far and near skies drift at 6 and 15 pixels per second using mirrored repetition.

Circle artwork stays behind the native slots and adjacency feedback; expansion changes the glowing seal while keeping the same logical slot coordinates. Card type, cost, mana production, rules and ship-coloured borders remain generated from live content. Captain portraits appear in preparation, assignment comparisons and editor previews. Unknown custom IDs keep a neutral artwork fallback. Button normal, hover and pressed textures are separate; their nine-slice textures are fitted at runtime without changing the original PNG files.

### Workshop sprite rigs

In **Editor → Enemies** or **Ships**, select an entry and choose **Sprites & animation…**. Start from any existing ship/creature template or an empty rig. Choose a prepared atlas slice, a full project PNG, or **Import PNG…** to copy a transparent image into `assets/imported/rigs/`. Importing adds an asset file; cancelling the dialog leaves that file available for later use.

Each part has a sprite region, rendered size, draw layer, local hinge, parent attachment, optional offset, rest rotation, flips and opacity. Link every part to one root body. In **Assembly**, drag a sprite to place its joint on its parent; in **Sprite**, click or drag its local hinge. Normalized U/V coordinates run from zero to one. Rotation oscillates around the hinge; period and phase coordinate the motion. Use zero vertical drift on limbs to keep their joints fixed, and small drift for balloons. Cables join editable sockets on any two parts and follow their movement. Referenced parts cannot be removed until their children/cables are reattached or removed.

Pause, scrub the timeline, inspect the rest pose, and toggle anchor markers in the live preview. **Apply to Workshop Draft** updates only that entry's draft; **Cancel** leaves it unchanged. **Save All** validates the complete rig and saves its `visual_rig` definition alongside the unit in `data/content.json`; **Save & Test Battle** uses it immediately. **Revert Unsaved Changes** restores the saved rig. Existing entries without an override keep their default art. Applying an empty rig chooses the neutral fallback.

The shared schema, preview and dialog live in `scripts/visuals/`. Rigs are declarative data, not executable scripts. Validation rejects missing sprites, out-of-bounds regions, missing/cyclic parent links and invalid motion values. The same anchored renderer is used in workshop, preparation, battle and results. Battle snapshots retain their own rig definitions, so later workshop edits cannot change an active battle or its result.
