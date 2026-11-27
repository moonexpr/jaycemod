# Dev workbench scenarios

Saved gameplay states, one JSON file per scenario under its map:
`<map>/<name>.json`. The dev server writes here through
`data/sandcastle_dev/scenarios`, a link `server_root.py` makes (`REPO_DATA`),
so a scenario worth keeping can be committed.

A file holds `format`, `name`, `description`, `map`, `schema`, `saved_at`
and `state` (a `dev.capture()`). `quick_<n>` files are the quicksave
slots; leave them out of commits.

Save, load, list and diff them on the server with `scenario_save`,
`scenario_load`, `scenario_list`, `scenario_diff`, `dev_quicksave` and
`dev_quickload` (the dev workbench: `addons/sandcastle_dev`, documented in
`CLAUDE.md`).
