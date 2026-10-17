# NextSoldier response rules

The AI war's soldiers speak through response rules modelled on TF2's
(the Source engine's `AI_ResponseSystem`, documented in TF2's
`scripts/talker/response_rules.txt`). This is a skeleton: the engine is
complete, and the content covers the payload cart.

## Pieces

| Piece | Where | Job |
|---|---|---|
| Engine | `foundation/core/response.lua` | criteria, rules, response groups, contexts; game-agnostic |
| Cart concepts | `foundation/payload.lua` `SpeedConcepts` | when the train watcher has players speak, as `team_train_watcher.cpp` does |
| Watcher | `entities/entities/team_train_watcher.lua` | raises `WSCartConcept(watcher, concept, audience, blocked)` |
| Content | `foundation/aiwar/speech.lua` | the soldiers' criteria, rules and lines |
| Speakers | `features/aiwar/sv_speech.lua` | who hears a concept, their criteria set, playing the line |

## How a line is chosen (as in TF2)

1. The watcher raises a concept: `TLK_CART_STOP` when the cart stops,
   `TLK_CART_MOVING_BACKWARD` when it starts back from standing (both to
   everyone), and `TLK_CART_MOVING_FORWARD` to the soldiers in the cart's
   capture area, at most every 3 s.
2. Each soldier that is alive and not still speaking builds its criteria set:
   `concept` (weight 5, as `CAI_Expresser` gives it), `teamrole` (`offense`
   for the cart's own team, else `defense`), `voice` (`foundation.npc.voices`'
   name), `randomnum` (0 to 100), `cartblocked` (1 when the enemy holds the
   cart), and its contexts.
3. Every rule is scored by the weights of the criteria it matches; a failed
   `required` criterion rules it out. The best score wins, and a tie is
   broken at random.
4. The rule's group says one line: every line is used before any repeats
   (unless `permitrepeats`), in order with `sequential`, never again after
   one round with `norepeat`. All soldiers share these repeats, as TF2's
   players do.
5. The rule's `ApplyContext` (`SaidCartMovingStoppedO:1:20`) is set on the
   speaker, so its `!=1` criterion keeps that soldier quiet on the concept
   for 20 s.

**Not in TF2:** a stop while the enemy blocks the cart (`cartblocked`) has
its own rules (`CartBlocked{Offense,Defense}`), which outscore the plain
stop by one required criterion. TF2 says only "stop".

## Adding to it

- **Lines:** edit `LINES` in `foundation/aiwar/speech.lua`. A line is
  `Speak(path)`, an HL2 sound (check it exists:
  `file.Exists("sound/" .. path, "GAME")`), or `Print(text)`, a placeholder
  shown only with `ns_speech_debug 1`.
- **A situation:** add it to `SITUATIONS` (its concept, role and context
  key) and give every voice lines for it. `tests/aiwar_speech_test.lua`
  fails for any voice left silent.
- **A concept:** raise it where the game decides it, as the watcher does,
  and listen for it in a feature part like `sv_speech.lua`.

Response kinds played are `speak`, `print` and `response` (a reference to
another group); TF2's `scene` and `sentence` are refused when the rules
are built, as is any rule naming a criterion or group that does not exist.

## Known

- A concept for everyone has every soldier that passes the 75 % chance and
  is not still speaking say a line at once, often 20 or more: true to TF2,
  but loud with 30 soldiers.
- `ns_speech_debug 1` prints each line with the rule that chose it.
