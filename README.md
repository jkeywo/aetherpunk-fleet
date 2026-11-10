# Aetherpunk Fleet

Godot 4.7 / GDScript / Compatibility renderer. Open `project.godot` and press **F5**.

The prototype includes a main menu, battle, victory/defeat summaries, and a live content editor. **Start Game** opens fleet preparation using saved content. **Retry Battle** replays the fleet you launched; editor playtests use the editor's saved setup. Results and running battles keep detached snapshots.

## Playing

Drag a card from the shared hand into an empty magic-circle slot. Choose any requested targets, optional resource boosts, then click other hand cards and/or temporary crystals to pay. **Resolve Card** commits the action; **Cancel Play** returns the pending card, payment, crystals, and resource reservations without firing abilities or consuming randomness.

The mana cost is locked on placement. Excess payment is lost. Main effects and allied chains finish before payment cards are discarded in click order and their discard abilities resolve. Newly exposed discard-top passives affect subsequent plays. After those chains finish, each represented enemy may react once, in formation order. Replacement stance cards cannot react to the action revealing them, including a one-card deck that replaces itself.

Hover cards, ships, circle slots, and enemy-row cards for complete generated rules. Green **BONUS** marks adjacent contributors; animated links show chained effects. Ships show hull, shields, armour, weapon, and personal resources. Stance cards show reaction conditions and enemy-phase activity.

### Fleet and preparation

Each of the three ships has a weapon, armour, and a named resource. Resources start at zero, persist between rounds, and reset on defeat. The initial capacity is six, before authored bonuses. Optional boosts reserve their resource before automatic spending rules evaluate.

Choose your fleet in **Main Menu → Start Game → Fleet Preparation**, then **Launch Battle**. Select ships, captains, starting positions, levels, and upgrade branches in the three ship panels. Occupied ship, captain, and position choices swap assignments, keeping the fleet unique. Level-3 menus hide the branch blocked by level 2; hover an upgrade option for its card pair, rule, and passive rewards. Effective stats, contributed cards, and formation update live. The editor's Battle Setup still supplies the authored defaults and encounter. Captains cannot be assigned twice. Each ship contributes its starter design twice and its captain's design twice. Level 2 and level 3 each add another pair, giving **4 / 6 / 8 physical cards per ship**. Each level-2 branch blocks one different level-3 package; the third level-3 package is available on either path. Tier labels the captain's authored power budget; it does not multiply statistics.

Preparation choices stay in the current session and never write content files. **Main Menu** remembers your draft; **Reset to Saved Fleet** restores authored defaults. If the saved fixed opening includes unavailable cards after your changes, launch uses a shuffled seven-card hand. You can also opt into a shuffled opening. **Retry Battle** resets the exact prepared snapshot; **Prepare Fleet** on normal result screens returns to selection. Editor playtests continue to use saved editor setup. Changed saved content resets stale preparation choices.

Initial provisional balance:

| Ship | Hull | Armour | Weapon | Resource |
| --- | ---: | ---: | --- | --- |
| Bastion | 28 | 2 | 4, Short | Resolve: mitigation and protection |
| Kestrel | 20 | 0 | 5, Long | Momentum: movement and attacks |
| Lamplighter | 18 | 1 | 3, Long | Aether: actual repair and support |

The shipped encounter starts at level 2 with Iona, Rook, and Voss, an 18-card fleet deck, and a fixed seven-card opening. Stormmaw contributes six stance cards, Storm Ray three, and Needlewing two. All balance values are editable.

### Formation, attacks, and basic actions

Both sides use Front, Upper Middle, Lower Middle, and Rear diamond positions. Short attacks cannot originate from Rear or target Rear. Movement earlier in an action changes the legal origin. Enemy attacks choose their matching position, except Rear attacks Front; otherwise they choose the first legal occupied position in Front, Upper, Lower, Rear order.

Each attack locks one target. Hits stop when it dies. Each hit resolves **slot cover → armour → shields → hull**. Armour reduces every hit without being consumed. Generic attack bonuses apply to the first hit; per-hit bonuses are separate chunks. Damage-threshold reactions use actual hull loss. Enemy-phase attacks retain escalation: +1 damage per round after round 3.

Drag a ship's own card onto it for a basic repair, or onto an adjacent living ally to swap. These actions discard the card without paying its printed mana cost or running its On Play rules. Repair restores 2 hull. A defeated ship accumulates recovery and revives with 4 hull when it reaches 4 recovery, occupying its former position if free, otherwise the first empty position. Recovery and movement have appropriate highlights and tooltips. The basic discard and actual repair/revival/movement can trigger authored rules.

### Magic circle, persistence, and rounds

The first four circle slots form a cycle. Filling all four expands it to nine spaces after the allied action. Centre touches all four original spaces; each new corner touches two. Original links remain. Positions never compact.

Played cards stay active through the enemy phase. At player-turn cleanup, a card starting with persistence loses one token and stays, including when it reaches zero. A card starting cleanup with zero tokens is discarded without On Discard abilities. Retained cards keep their exact positions and adjacency; they do not replay On Play. Expansion lasts until the circle is entirely empty.

At **End Fleet Phase**, holding at least two cards earns one temporary mana crystal at the next player turn, subject to capacity (normally one). Unspent crystals expire when ending the fleet phase. Click crystals during pending payment; they provide one mana and cannot satisfy discard effects. Generation and capacity can be modified by rules.

The three visible enemy cards activate left to right, discarding and replacing each afterward. Multiple cards can activate one enemy repeatedly. Replacements add no activations to that phase. Each surviving enemy that had no activation performs its weaker default action afterward. Defeated enemies' cards leave the shared row and pool.

After enemy actions, shields and cover expire, persistence cleanup runs, turn limits reset, and earned mana is granted. Retain your hand, optionally click cards to discard, then refill to seven. These deliberate discards can trigger abilities. Win after defeating all enemies while a ship survives; lose when the fleet is destroyed. Results report surviving ships, remaining hull, and rounds.

### Control and hidden information

**Stun** suppresses one selected visible reaction until fleet-phase end; enemy activity continues. **Confuse** discards and replaces one selected row card. **Scry** reveals up to X available deck cards, takes Y into hand, and lets you order the rest back on top or discard them. Mandatory discard and scry suspend the committed queue. Revealed decisions must be completed; Cancel Play cannot undo hidden information.

Previews run the same registered effects on detached state. They show known public effects and mark uncertainty, without consuming live RNG or revealing draw/replacement identities.

## Content editor and rules

**Editor** has searchable Enemies, Ships, Captains, and Cards tabs with New, Duplicate, and Delete. Stable IDs survive renames. Referenced entries cannot be deleted until their loadouts, ownership, or setup references change.

The right panel contains shared in-game previews and Battle Setup. Configure fleet order, captains, levels, legal branches, one to four enemy instances, fixed/random opening hand, mana defaults, and basic-action values. Each enemy contributes editable stance designs with copy counts and has a separate weaker default action.

Rules are reusable **code-defined chunks** in `scripts/rules/rule_registry.gd`. Data contains IDs and parameters, never executable scripts. The registry owns typed schemas, validation, editor fields, generated text, and handlers. The generic rule editor combines triggers, boolean conditions, optional resource costs, ordered effects, and passive modifiers. See [docs/RULE_CHUNKS.md](docs/RULE_CHUNKS.md) for authoring and execution details.

**Save All** validates and writes `data/content.json`. It creates no Git commit. **Revert Unsaved Changes** restores saved content. **Save & Test Battle** saves first, then launches a battle with Return to Editor in its menu and results. Leaving a dirty draft offers Save, Discard, or Cancel. Failed validation/writes preserve the previous save.

Content version 3 includes progression, captains, composable rules, and the shared enemy deck. Versions 1 and 2 migrate in memory without rewriting files until Save. IDs, imported decks, and supported effects are retained. Imported cards are explicitly flagged if they do not meet the new 2–3-block convention; migration does not invent abilities. The immutable `gdd_content.json`, `diamond_content.json`, and `fleet_content.json` fixtures isolate regressions from live design edits.

## Verification

With the Godot console executable on PATH:

```powershell
godot --headless --path . --editor --import --quit
./tests/run_tests.ps1 -Godot godot
```

Tests cover registry metadata/forms/execution, immutable migrations and failed saves, physical pair assembly and branches, resources and boosts, payment cancellation, mana, persistence, armour/multi-hit/range, enemy ownership/replacements/defaults, control effects, hidden decisions, native drag/drop, animated feedback, results/retries, and editor playtests. UI checks use a 1280 × 800 viewport; editor and battle content scroll in smaller windows.

Campaign progression, XP, acquisition, production art, and custom content scripts remain outside this prototype.
