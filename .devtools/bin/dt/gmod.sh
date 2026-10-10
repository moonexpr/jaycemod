#!/bin/sh
# dt-brief: Call a gmod MCP tool (dt gmod lua_errors since=3), for ctx_batch_execute
exec python3 "$(dirname "$0")/../gmod_mcp.py" call "$@"
