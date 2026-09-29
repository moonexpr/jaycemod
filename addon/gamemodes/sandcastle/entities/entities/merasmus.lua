-- merasmus (CMerasmus): a stub. TF2's Merasmus is 1600 lines of boss with
-- bomb heads, props, the Wheel of Fate and minigames, none of which
-- Sandcastle has; porting him is out of scope for pass 3. pl_rumble_event
-- and pl_fifthcurve_event spawn him from a point_template and Kill him at
-- each round start, so the stub keeps its keyvalues, logs once, and removes
-- itself as soon as it spawns. Kill is the engine's.
ENT.Type = "point"
ENT.Base = "wetsand_stub_point"

ENT.StubReason = "Merasmus is not supported; removed on spawn"
ENT.StubRemoves = true
