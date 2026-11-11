---
name: glua-style
description: >
  GLua Best Practices - the style guide for Garry's Mod (GLua) code.
  Use when writing, reviewing, or refactoring any GLua/Lua code.
  Covers formatting, naming conventions (camelCase, SCREAMING_SNAKE,
  PascalCase), hook and net message naming, GLua-specific anti-patterns
  (GMod operators), file structure and realms. Load before writing GLua
  code and apply these rules to your output.
---

# GLua Best Practices

Use these rules when writing, reviewing, or refactoring GLua (Garry's Mod) code.
Follow them exactly.

These rules target beginner-level output and AI agents; experienced developers may deviate — stay consistent.

## Usage

1. Read this file before writing any GLua code.
2. For a full example of a compliant file, read `references/example-good.lua`.
3. For the contrasting example, read `references/example-bad.lua`.
4. For a compact rule summary in code form, read `references/style-rules.lua`.
5. After writing code, verify it against the checklist at the bottom of this file.

## Formatting

In Sandcastle, layout is notcake's (gcompute, glib), written by `.devtools/bin/lua_format.py`; where a rule below disagrees with it (space before `(`, table braces, trailing commas), the formatter and CLAUDE.md's "Lua style" win.

- Indent with tabs (4-space tab stop). Never use spaces for indentation.
- You may use an extra indentation level to visually group code between paired calls (e.g. `cam_Start3D`/`cam_End3D`, `render.PushRenderTarget`/`render.PopRenderTarget`).
- Put spaces around binary operators: `a + b`, never `a+b`.
- Never put spaces inside parentheses: `(3 * myFunc())`, not `( 3 * myFunc() )`. Empty pairs stay tight: `myFunc()`. The spaced style is a legacy convention that breaks with autoformatters.
- Prefer compact curly braces: write `{5, {}}`. This one is a preference, not a requirement — the repo formatter rewrites tables as `{ 5, {} }` and cannot be configured otherwise, so both forms occur in conforming code.
- Put a space after commas: `myFunc(10, {3, 5})`.
- Do not put spaces inside square brackets: `tab[5]`, `tab[5 * 3]`.
- Put a single space after comment markers and before inline comments: `-- comment`, `local a = 3 -- comment`.
- Keep lines at ~110 characters (soft target); 120 characters is the hard limit. This applies to comments too.

## Newlines

- Never use more than 1 consecutive blank line.
- Separate top-level blocks with a single blank line. Don't add restating header comments (e.g. `-- Think` above a `Think` hook) — rely on blank lines and meaningful names.
- Never use more than 1 newline inside a function body.
- Put one newline before `return` unless the block is a single line. Exception: guard-clause chains — no blank line needed between consecutive early returns and the final return.
- Split code into manageable chunks with single blank lines.

## GLua specifics

- Never use GMod operators (`&&`, `||`, `!`, `!=`). Use `and`, `or`, `not`, `~=`.
- Never use GMod comments (`/* */`, `//`). Use `--` and `--[[ ]]`.
- GMod's `continue` is fine for simple filters. (It is error-prone inside `repeat-until` loops — prefer a plain loop there.)
- Hook return semantics: only return a value from a hook when you intend to override or block the default behaviour. If your condition fails, return nothing — returning `false` blocks the hook for every other addon and the game's default logic. When detouring a function, always call the original; think about backwards compatibility and unintended consequences when detouring a public API.

## Naming

- Locals and local functions: camelCase (`myVariable`).
- Constants: SCREAMING_SNAKE (`MAXIMUM_VALUE`). A constant is a value treated as fixed by design — literals, configuration, lookup tables and cached objects used as read-only (`MAX_PLAYERS`, `ALLOWED_ROLES`, `PLAYER_COLOR`). Actual immutability is not enforced; references to mutable *state* (counters, accumulators) are regular locals/globals. This applies to global constants too: `MAX_PLAYERS = 32`, not `MaxPlayers = 32`.
- Globals: PascalCase for mutable values — namespace tables, config tables, counters (`GlobalVariable`). Most addons need at least one namespace global — embed the org name in it (`ValvePrinters`, `RubatSkillsSystem`), preferably one global per addon (soft cap of 5), and keep addon data inside the namespace table. Global constants are SCREAMING_SNAKE per the constants rule.
- Object methods and library functions: PascalCase (`function classTable:SetHealth(amount)`, `function someLib.ResolveFilter(filter)`). camelCase dot-functions (e.g. `math.floor`) are bad style.
- Table keys accessed via dot notation: only `a-z A-Z 0-9`, `.` and `_`; must not start with a digit. Keys used only via brackets (`t["my-value"]`) and integer array indices are unrestricted.
- Use `_` for throwaway values: `for _, ply in ipairs(...)`.
- Hook identifiers: `orgName/productName/eventPurpose` — namespaced paths with slashes and hyphens (e.g. `gmod.one/true-printers/cleanup-props`). Do not include the event name in the identifier (`orgName/productName/on-disconnect` is wrong; `orgName/productName/cleanup-props` is right).
- Custom hook events (`hook.Run`): same namespaced format, `orgName/productName/eventName` (e.g. `gmod.one/myaddon/player-count-changed`).
- Net message names: same namespaced style, e.g. `gmod.one/myaddon/player-count`.

## General

- Always use double quotes — one style for the whole codebase, no mixing. Escape inner double quotes with backslashes: `"say \"hi\""`. Never use single quotes. For strings with many quotes or line breaks, use long bracket strings (`[[...]]`) instead of escaping everything.
- Do not use redundant parentheses around conditions. They are acceptable when they make operator precedence clearer.
- Explicit comparisons: prefer `x == false` / `x ~= true` when the value is guaranteed boolean (e.g. `IsValid`, `ply:Alive())` — it states intent. This is a recommendation, not a requirement: `not x` is idiomatic and fine, especially for nil checks (`not x` catches `nil`, `x == false` does not). Stay consistent.
- Multiline tables and function calls: elements on their own lines, indented once, closing bracket on its own line. A multiline table passed as an argument follows the same rules; a short nested table may be passed compactly. Multiline tables keep a trailing comma after the last element (StyLua adds it automatically); argument lists must not have one — a comma before `)` is a syntax error:

```lua
surface.CreateFont("MyFont", {
	font = "Arial",
	size = 13,
	weight = 500,
})

myFunc("First arg", secondArg, {
	v1 = firstValue,
	v2 = secondValue,
})

myFunc(
	"First arg",
	secondArg,
	{third, arg}
)
```
- Return early from functions instead of nesting.
- Pull magic numbers into named variables. This applies to bare literals in logic (conditions, arithmetic, calculations). Configuration data grouped in named config tables/constants (prices, timings, limits) is not magic.
- Write complex expressions as multiple named steps.
- Write complex Lua string patterns on multiple lines using `table.concat` — one-line pattern strings full of escapes are unreadable. Patterns are constants: build them once at file scope, never in a hot loop. Long bracket strings break on newlines/whitespace — don't use them for patterns.
- Never use semicolons.
- Use existing constants (`math.pi`) instead of literals.
- Pull long conditions into named variables, but note named conditions evaluate eagerly — prefer flat early returns for expensive checks. If splitting a condition across lines, put operators at the start of each line.
- Numbers: `0.5` not `.5`; `420` not `00420`; `0.2` not `0.200`.

## Comments

- Comments are an exception, not a default. Add one only where the code cannot explain itself (non-obvious logic, workarounds, external constraints).
- Never add comments that restate the code (`-- set player`) or section-label noise. Beginners and AI models tend to over-comment — don't.

## Practices

- Avoid unnecessary `IsValid` checks: only guard code where the entity can actually become invalid (e.g. delayed timers). In hooks like `PlayerInitialSpawn` or inside `net.Receive` the player is guaranteed valid.
- Use `print` varargs instead of string concatenation: `print("Health:", ply:Health())`. Use `string.format` when you need control over the output (precision, alignment, values mid-string).
- Do not call `tostring` on values that are already coerced (e.g. numbers in concatenation).
- Globals: use them deliberately. One namespace global per addon with the org name embedded (`ValvePrinters = ValvePrinters or {}`), soft cap of 5, addon data kept inside the namespace table. Keep state file-local when nothing outside the file needs it; a module return is the preferred way to share values when sharing is actually needed. Use `local function` for file-internal helpers; global `function ValvePrinters.Foo()` only when other files need to call it.
- Destructure `require` results: `local hmac = require("openssl").hmac.hmac`.
- Prefer stable APIs over ones still marked experimental: avoid the `GetNW2Var`/`SetNW2Var` family entirely (GmodStore disallows it, see garrysmod-issues #5455; the API has been marked experimental for years and may change without notice) — use the stable typed counterparts (`GetNWInt`/`SetNWInt`, `GetNWBool`/`SetNWBool`, `GetNWString`/`SetNWString`, `GetNWFloat`, `GetNWEntity`, `GetNWAngle`, `GetNWVector`). There is no generic `SetNWVar` — the stable family is typed by design. Avoid deprecated APIs in new code: `umsg` (use `net`), `self.Owner` (use `GetOwner()`), `self.Weapon` in SWEPs (self is already a weapon, dont need self.Weapon). Prefer the `net` library over network variables; NWVars are for data read every frame where a net message is impractical.
- Keep nesting depth at three levels or fewer. If a function can't stay flat, split it into several compact sub-functions, each doing one thing.
- Localize frequently used globals at the top of hot files (Think hooks, render loops, tick): `local IsValid = IsValid`, `local RealTime = RealTime`. This skips global table lookups on every call. Verify hot paths with a profiler first and localize what it flags, not everything. LuaJIT caps upvalues per function at 60 — don't overdo it.
- Cache objects (`Color`, `Material`, `Vector`, `Angle`) once at file scope — never construct them per frame in `DrawHUD`, `Think` or render loops. Add a `DistToSqr` distance check before world-space (3d2d) drawing, plus a visibility check (`CamIsVisible`) where it matters.
- Register net messages with `util.AddNetworkString` only on the server, at the top of the file or in init — never inside hooks or dynamic functions.
- Networking: prefer typed writers (`net.WriteUInt`, `net.WriteInt`, `net.WriteFloat`) over `net.WriteType`/`net.WriteTable` (expensive). Send references (keys), not data the client already has; never send data the client doesn't use. Rate-limit player-triggered messages server-side (per-player cooldown); debounce client-side before `net.SendToServer()`; validate incoming types, minimize client-to-server traffic, and keep all authoritative checks server-side — never use `SendLua`/`BroadcastLua`, always verify the sender in `net.Receive`. Never write DataTable vars or send net messages from per-frame hooks (`Think`, `Move`) — update on change, not per frame.
- Iteration: prefer `ipairs` or a numeric `for i = 1, #t` loop over `pairs` on sequential numeric tables (~4x faster). Use keyed lookup tables (`{["admin"] = true}`) over `table.HasValue` scans. Never loop `player.GetAll()`/`ents.GetAll()` in Think hooks — use `player.Iterator()`/`ents.Iterator()` or cache the list and refresh on spawn/disconnect. Both iterators behave like `ipairs`: write `for _, ply in player.Iterator() do` — the first loop variable is the numeric index, not the player.
- Cap tables that grow with unbounded input (logs, caches) — implicitly by player count or explicitly with a max size.
- Code safety: validate data state and permissions before risky operations; never remove entities or change `PhysObject` inside touch/collision hooks — use `SafeRemoveEntityDelayed`. Touch and collision callbacks are `ENTITY:` methods (`function ENT:StartTouch(other)`), not `hook.Add` events.
- Error handling: do not wrap code in `pcall` by default. A Lua error in GMod does not crash the process — it prints to console and aborts only the current call. Use `pcall` only where the function must be guaranteed to complete (a loop where one failing item must not abort the rest, a risky step followed by mandatory cleanup) or for narrow cases: parsing untrusted input, calling foreign callbacks, touching a third-party API that may be absent. Always report a caught error with `ErrorNoHalt`/`ErrorNoHaltWithStack` — never swallow it. Use `ProtectedCall(func, ...)` when a success flag is enough and the error should still be printed.
- Scale UI: no hardcoded pixel sizes for major elements — use `ScrW()`/`ScrH()` proportions (cache them at file scope, refresh in `GM:OnScreenSizeChanged`) and handle `GM:OnScreenSizeChanged`, re-creating fonts/materials there.
- Credit borrowed code: comment the author and make sure you have permission for commercial use.
- Respect realm separation: never write `if SERVER then return end` at the top of a file — use file placement instead. `lua/autorun/*.lua` loads on both realms, `autorun/server/*` only on the server, `autorun/client/*` only on the client. Exactly one autorun file per addon (never a shared path like `lua/autorun/init.lua` — VFS loads only one of colliding paths; use a unique name), limited to loading other files; keep all files inside your own uniquely named folder — when integrating with another addon, write only your own uniquely named file into its module folder. Avoid massive megafiles — split into logical modules. Shared files are included on both sides (`AddCSLuaFile` + `include`); server-only files must never be added via `AddCSLuaFile` (it leaks server code to scriptkiddies). Avoid heavy `if SERVER`/`CLIENT` branching in shared code — split the logic into realm-specific files when it diverges.

## Checklist (verify before finishing)

- [ ] Tab indentation, no space-indented blocks
- [ ] No spaces inside parens (`f(x)`) or square brackets (`tab[5]`); compact braces preferred (`{5, {}}`)
- [ ] Double quotes only, escaped when needed
- [ ] No GMod operators or GMod comments; `continue` only in plain loops
- [ ] Net messages registered server-side at init; no `if SERVER then return end` at file top
- [ ] Locals camelCase, constants SCREAMING_SNAKE (immutable values), globals PascalCase
- [ ] Throwaway values use `_`
- [ ] Hook identifiers `orgName/productName/eventPurpose`, no event name inside
- [ ] No redundant parentheses, no semicolons, no magic numbers in logic (config data is fine)
- [ ] Explicit comparisons preferred for guaranteed-boolean values; `not` fine for nil checks (recommendation, be consistent)
- [ ] Lines ~110 chars (hard limit 120), comments included
- [ ] No useless/restating comments; comments only where code can't explain itself
- [ ] No unnecessary `IsValid` checks
- [ ] Globals: unique namespace name, soft cap 5, no bare globals
- [ ] Nesting depth <= 3
- [ ] Hook returns: nothing unless blocking; detours call the original
- [ ] Net: typed writers, rate limiting + validation, server-side authority
- [ ] No deprecated APIs (umsg, self.Owner, self.Weapon); no NW2Var
- [ ] Code safety: SafeRemoveEntityDelayed in touch/collision hooks; state validated
- [ ] `pcall` only where completion must be guaranteed; errors logged, never swallowed
