# NextSoldier response rules

The AI war's soldiers speak through response rules modelled on TF2's (the
Source engine's `AI_ResponseSystem`, documented in TF2's
`scripts/talker/response_rules.txt`). The engine, the parser and every rule
live in their own addon, `addons/responserules/`; nothing a soldier says is
written in Lua.

## The addon

| Piece | Where | Job |
|---|---|---|
| Engine | `lua/includes/modules/responserules.lua` (`require "responserules"`) | criteria, rules, response groups, contexts; game-agnostic |
| Parser | `lua/includes/modules/responserules_script.lua` (`require "responserules_script"`) | TF2's talker grammar into the engine's definitions |
| Service | `lua/autorun/server/responserules.lua` | loads the rules, the global `ResponseRules`, its commands |
| Rules | `scripts/responserules/response_rules.txt` | the root: shared criteria, `#include`s |
| | `scripts/responserules/combine.txt`, `rebel.txt` | the rules, by the speaker model's affiliation |

The service reads `scripts/responserules/response_rules.txt` from the GAME
path, which every mounted addon is on, and follows its `#include`s
(relative to `scripts/`). The dedicated server links the addon into its
`addons/` (`.devtools/bin/server_root.py`, `REPO_ADDONS`).

Console: `responserules_reload` reads the files again (a refused file leaves
the rules as they were and says why, with its file and line),
`responserules_print` says what is loaded, `responserules_debug 1` prints
each line said and the rule that chose it.

## In Sandcastle

| Piece | Where | Job |
|---|---|---|
| Cart concepts | `foundation/payload.lua` `SpeedConcepts` | when the train watcher has players speak, as `team_train_watcher.cpp` does |
| Watcher | `entities/entities/team_train_watcher.lua` | raises `WSCartConcept(watcher, concept, audience, blocked)` |
| Criteria | `foundation/aiwar/speech.lua` | a soldier's criteria set |
| Speakers | `features/aiwar/sv_speech.lua` | who hears a concept; plays the line |
| Sides | `foundation/npc/voices.lua` | each voice's name and affiliation |

A soldier's criteria set: `affiliation` (`combine`, `rebel`), `voice`
(`combine`, `metrocop`, `male`, `female`, `alyx`, `vortigaunt`), `teamrole`
(`offense` for the cart's own team, else `defense`), `randomnum` (0 to 100),
`cartblocked` (1 while the enemy holds the cart), and the contexts its rules
applied.

## Rules by affiliation, not team

A team may wear either side's models, so a soldier answers by its own
model's side. Each situation has, in its affiliation's file:

- a rule for the affiliation, with placeholder `print` lines, so any model of
  that side answers, a new one included, once `foundation.npc.voices` gives
  it its affiliation;
- a rule for each voice with lines of its own, which outscores it by its
  `voice` criterion.

A stop while the enemy blocks the cart (`cartblocked`, weight 2) outranks a
voice's plain stop, so the cut-off lines win even where only the affiliation
has them. TF2 itself says only "stop" then.

## How a line is chosen (as in TF2)

1. The watcher raises a concept: `TLK_CART_STOP` when the cart stops,
   `TLK_CART_MOVING_BACKWARD` when it starts back from standing (both to
   everyone), `TLK_CART_MOVING_FORWARD` to the soldiers in the cart's capture
   area, at most every 3 s.
2. Each soldier that is alive and not still speaking builds its criteria
   set; the concept weighs 5, as `CAI_Expresser` gives it.
3. Every rule is scored by the weights of the criteria it matches; a failed
   `required` criterion rules it out. The best score wins; a tie is broken at
   random.
4. The rule's group says one line (each used before any repeats, unless
   `permitrepeats`; `sequential`; `norepeat`), within its `odds`; after it,
   the speaker waits the group's `delay` (`defaultdelay`: 2.8 to 3.2 s), and
   the group sets how loud it is (`soundlevel`, default `SNDLVL_TALKING`).
   All speakers share the groups' repeats, as TF2's players do.
5. The rule's `ApplyContext` (`SaidCartMovingStoppedO:1:20`) is set on the
   speaker, so its `!=1` criterion keeps that soldier quiet on the concept
   for 20 s.

## Writing rules

The files are TF2's talker grammar: `criterion`, `response`, `rule`,
`enumeration`, `#include`, `//` comments. As in Source, a criterion's
options, a line's options and a rule's lists end with their line.

- A line is `speak "<sound path>"` (check it exists:
  `file.Exists("sound/" .. path, "GAME")`), `print "<text>"` (a placeholder,
  shown with `responserules_debug 1`), or `response <group>`.
- A new situation: a rule and group in each affiliation's file;
  `tests/aiwar_speech_test.lua` fails for any voice left silent.
- A new side: an affiliation in `foundation/npc/voices.lua`, and its file
  included from `response_rules.txt`.

Refused when loaded, naming the file and line (Source warns and goes on):
TF2's `scene` and `sentence` lines, `predelay`, `weapondelay`,
`stop_on_nonidle`, `displayfirst`, `displaylast`, `applyContextToWorld`, an
unknown option, a second definition of a name, a name a rule uses but
nothing defines.

## Known

- A concept for everyone has every soldier that passes the 75 % chance and
  is not still speaking say a line at once, often 20 or more: true to TF2,
  but loud with 30 soldiers.
- Some rebel lines name the enemy ("Combine!"), which is wrong when the enemy
  wears rebel models; an `enemyaffiliation` criterion would choose them.
