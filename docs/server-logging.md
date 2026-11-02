# Server logging

Server logs are emitted through `WS.Logger(subsystem)`, which adds a colored
subsystem prefix and writes only when that subsystem is enabled in `con_spew`.
The convar accepts a space-separated list; for example:

```text
con_spew "rounds payload capture"
```

Set `con_spew ""` to disable these logs. Available subsystems are `capture`,
`defuse`, `flag`, `gamerules`, `hostage`, `payload` and `rounds`. Console
completion suggests names not already selected.
