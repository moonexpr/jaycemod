# devtools-audit

**Question:** what lives in `.devtools/bin` and `.claude`, how the harness came to be this way, and
whether it earns its keep. The answer is the report of 2026-11-13
(`.devtools/artifacts/devtools-report-2026-11-13.pdf`; a copy in iCloud), whose Section 10 the
cleanup follows.

| Script | Does |
|---|---|
| `transcript_toolkit.py` | Classifies every tool call in Claude Code's transcripts for this project; writes the aggregates as JSON |
| `devtools_report.py` | Writes the report from the folder, the history, devrag's log and those aggregates |

Status: answered; kept until the cleanup it ordered is done, then deleted.
