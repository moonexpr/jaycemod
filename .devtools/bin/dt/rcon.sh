#!/bin/sh
# dt-brief: Send a console command over RCON (dt rcon [--instance N] "status")
# srcds.py takes --instance before its subcommand; this takes it first too.
instance=""
if [ "$1" = "--instance" ]; then instance="--instance $2"; shift 2; fi
exec python3 "$(dirname "$0")/../srcds.py" $instance rcon "$@"
