# Source SDK 2013, the parts native/ builds against

Raw files from Valve's Source SDK 2013 (github.com/ValveSoftware/source-sdk-2013,
the commit in `COMMIT`), under the SDK's own paths and unmodified, with the
`LICENSE` and `thirdpartylegalnotices.txt` its licence requires to travel with
them. Copyright (c) Valve Corporation; distributed free of charge under the
Source 1 SDK License, for a modified Valve game on the Source 1 engine.

`native/wetsands/build.rs` reads the values these headers name (every enum's
members, the constants outside `#if`s) into `wetsands::source::<header>`
under their Source names, so native code uses Source's own interface:
`source::nav::NAV_MESH_CROUCH`, `source::nav_pathfind::FASTEST_ROUTE`,
`source::tf_nav_area::TF_NAV_SPAWN_ROOM_RED`. The other headers
(`nav_area.h`, `NextBotPath.h`) are kept as the reference the ports follow
(`CNavArea`, `IPathCost`).

Refresh from a local clone with `.devtools/bin/vendor_source_sdk.sh`.
