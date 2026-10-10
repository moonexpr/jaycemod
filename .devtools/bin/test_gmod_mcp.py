"""gmod_mcp.py: the MCP protocol over stdio, each tool's call against a fake
server, and what the answers read like."""
import io
import json
from pathlib import Path

import pytest

from gmod_mcp import TOOLS, Mcp, plain, run_call, show_errors, show_hits, show_stack, tail
from server_lua import BridgeDown, OpFailed, Realm, Reply


class FakeServer:
    """Stands for the dedicated server: records each call and answers from a table."""

    def __init__(self, answers=None, log_text="", watch_text=""):
        self.calls = []
        self.answers = answers or {}
        self.log_text, self.watch_text = log_text, watch_text

    def lua(self, realm, code, instance):
        self.calls.append(("lua", realm, code, instance))
        return self.answers.get("lua", Reply(["printed"], ["42"], None, None))

    def op(self, name, args, instance):
        self.calls.append(("op", name, args, instance))
        answer = self.answers.get(name)
        if isinstance(answer, Exception):
            raise answer
        return answer

    def rcon(self, command, instance):
        self.calls.append(("rcon", command, instance))
        return "hostname: test"

    def console_log(self, instance):
        return self.log_text

    def watch_log(self, instance):
        return self.watch_text


def session(server, *requests):
    """Runs the requests through Mcp, returning the replies by id."""
    stdin = io.StringIO("".join(json.dumps(r) + "\n" for r in requests))
    stdout = io.StringIO()
    Mcp(server, Path("/listeners")).serve(stdin, stdout)
    return {r.get("id"): r for r in map(json.loads, stdout.getvalue().splitlines())}


def call(server, tool, **arguments):
    reply = session(server, {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                             "params": {"name": tool, "arguments": arguments}})[1]
    result = reply["result"]
    return result["content"][0]["text"], result.get("isError", False)


def test_initialize_answers_the_clients_protocol_version_and_offers_tools():
    replies = session(FakeServer(), {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                     "params": {"protocolVersion": "2025-06-18", "capabilities": {}}})
    result = replies[1]["result"]
    assert result["protocolVersion"] == "2025-06-18"
    assert "tools" in result["capabilities"]
    assert result["serverInfo"]["name"] == "gmod"


def test_a_notification_gets_no_reply():
    assert session(FakeServer(), {"jsonrpc": "2.0", "method": "notifications/initialized"}) == {}


def test_an_unknown_method_is_a_json_rpc_error():
    reply = session(FakeServer(), {"jsonrpc": "2.0", "id": 7, "method": "resources/list"})[7]
    assert reply["error"]["code"] == -32601


def test_tools_list_names_every_tool_with_a_schema():
    tools = session(FakeServer(), {"jsonrpc": "2.0", "id": 1, "method": "tools/list"})[1]["result"]["tools"]
    names = {t["name"] for t in tools}
    assert {"lua_run", "rcon", "console_log", "lua_errors", "breakpoint_set", "breakpoint_list",
            "breakpoint_clear", "breakpoint_hits", "debug_state", "debug_eval", "debug_resume",
            "watch_events", "listeners"} <= names
    for t in tools:
        assert t["inputSchema"]["type"] == "object", t["name"]
        assert t["description"], t["name"]


def test_lua_run_prints_output_then_returns():
    server = FakeServer()
    text, failed = call(server, "lua_run", code="return 42", realm="sh", instance=2)
    assert (text, failed) == ("printed\n=> 42", False)
    assert server.calls == [("lua", Realm.SHARED, "return 42", 2)]


def test_lua_run_defaults_to_the_server_realm_on_the_main_instance():
    server = FakeServer()
    call(server, "lua_run", code="x")
    assert server.calls == [("lua", Realm.SERVER, "x", 1)]


def test_a_lua_error_is_an_error_result_with_what_printed_before_it():
    server = FakeServer({"lua": Reply(["half"], [], "server_lua:1: boom", None)})
    text, failed = call(server, "lua_run", code="error('boom')")
    assert failed
    assert text == "half\nERROR server_lua:1: boom"


def test_a_server_that_is_down_is_an_error_result_saying_so():
    server = FakeServer({"bp_list": BridgeDown("127.0.0.1:27098 not reachable")})
    text, failed = call(server, "breakpoint_list")
    assert failed and "not reachable" in text


def test_an_op_that_refused_is_an_error_result_with_its_reason():
    server = FakeServer({"bp_clear": OpFailed("no breakpoint 9")})
    text, failed = call(server, "breakpoint_clear", id=9)
    assert (text, failed) == ("no breakpoint 9", True)


def test_an_unknown_tool_is_an_error_result():
    text, failed = call(FakeServer(), "nope")
    assert failed and "nope" in text


def test_breakpoint_set_passes_only_what_was_given():
    server = FakeServer({"bp_set": {"id": 3, "file": "foundation/x.lua", "line": 9, "mode": "pause",
                                    "state": "active", "hits": 0, "max": 5}})
    text, _ = call(server, "breakpoint_set", file="addon/gamemodes/sandcastle/gamemode/foundation/x.lua",
                   line=9, mode="pause")
    assert server.calls == [("op", "bp_set", {"file": "addon/gamemodes/sandcastle/gamemode/foundation/x.lua",
                                              "line": 9, "mode": "pause"}, 1)]
    assert text.startswith("bp3 foundation/x.lua:9 pause active 0/5")


def test_rcon_answers_the_reply():
    server = FakeServer()
    assert call(server, "rcon", command="status", instance=2) == ("hostname: test", False)
    assert server.calls == [("rcon", "status", 2)]


FRAME = {"name": "BpProbe", "source": "server_lua", "line": 2,
         "locals": [{"name": "x", "value": "5"}], "upvalues": [{"name": "bonus", "value": "10"}]}


def test_a_stack_reads_frame_by_frame_with_locals_and_upvalues():
    assert show_stack([FRAME, {"name": "Outer", "source": "server_lua", "line": 6, "locals": {}, "upvalues": {}}]) == (
        "#1 BpProbe  server_lua:2\n"
        "   locals: x=5\n"
        "   upvalues: bonus=10\n"
        "#2 Outer  server_lua:6"
    )


def test_hits_read_one_stack_each():
    text = show_hits([{"n": 1, "time": 12.5, "frames": [FRAME]}])
    assert text.splitlines()[0] == "hit 1 at 12.50"
    assert "#1 BpProbe  server_lua:2" in text


def test_no_hits_says_so():
    assert show_hits({}) == "no hits yet"


def test_errors_read_message_count_and_stack():
    text = show_errors([{"id": 4, "seq": 4, "time": 3.0, "last": 3.0, "error": "x.lua:9: boom", "count": 1,
                         "realm": "server", "stack": [{"File": "x.lua", "Function": "Boom", "Line": 9}]}])
    assert text == "error 4 (seq 4) first 3.00, last 3.00 (x1, server): x.lua:9: boom\n   Boom  x.lua:9"


def test_console_text_loses_its_terminal_codes():
    assert plain("\x1b[?25h\x1b]0;My Server\x07\x1b[39mhello\r\n") == "hello\n"


def test_tail_keeps_the_last_lines_matching_a_pattern():
    text = "a 1\nb 2\na 3\na 4\n"
    assert tail(text, 2, "^a") == "a 3\na 4"
    assert tail(text, 10, None) == "a 1\nb 2\na 3\na 4"


def test_console_log_is_the_plain_tail_of_the_servers_log():
    server = FakeServer(log_text="\x1b[39mone\ntwo\nthree\n")
    assert call(server, "console_log", lines=2) == ("two\nthree", False)


def test_watch_events_filter_by_name():
    server = FakeServer(watch_text="1.00 nav progress opening\n2.00 bp1 hit x:3\n3.00 nav met 4 areas\n")
    assert call(server, "watch_events", name="nav")[0] == "1.00 nav progress opening\n3.00 nav met 4 areas"


def test_listeners_names_each_with_its_first_comment_line_and_how_to_follow_it(tmp_path):
    (tmp_path / "nav_generate.lua").write_text("-- Follows mp_nav_generate to its end.\n-- more\nWatch.Task()")
    out = io.StringIO()
    Mcp(FakeServer(), tmp_path).serve(io.StringIO(json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "listeners", "arguments": {}}}) + "\n"), out)
    text = json.loads(out.getvalue())["result"]["content"][0]["text"]
    assert "nav_generate: Follows mp_nav_generate to its end." in text
    assert "server_watch.py --listen NAME --run 'COMMAND'" in text


def test_every_tool_has_a_handler():
    assert all(callable(t.handler) for t in TOOLS)


def test_game_events_read_one_line_each_with_fields_and_recipients():
    server = FakeServer({"game_events": [
        {"id": 7, "time": 3.5, "name": "nav_progress", "players": 2,
         "fields": [{"name": "areas", "value": "0"}, {"name": "stage", "value": "1"}]}]})
    text, _ = call(server, "game_events", name="nav_progress", since=6)
    assert text == "7 at 3.50 nav_progress -> 2 players: areas=0 stage=1"
    assert server.calls == [("op", "game_events", {"name": "nav_progress", "since": 6}, 1)]


def test_no_game_events_says_so():
    assert call(FakeServer({"game_events": {}}), "game_events")[0] == "no game events"


def test_console_messages_read_one_line_each():
    server = FakeServer({"console_messages": [{"id": 3, "time": 1.0, "text": "[Sandcastle] ready"}]})
    text, _ = call(server, "console_messages", grep="Sandcastle")
    assert text == "3 at 1.00 [Sandcastle] ready"
    assert server.calls == [("op", "console_messages", {"grep": "Sandcastle"}, 1)]


def test_errors_show_their_change_number_for_since():
    text = show_errors([{"id": 4, "seq": 9, "time": 3.0, "last": 5.0, "error": "boom", "count": 2,
                         "realm": "server", "stack": {}}])
    assert text == "error 4 (seq 9) first 3.00, last 5.00 (x2, server): boom"


def test_a_command_line_call_prints_the_tools_text_for_context_mode_to_index():
    server = FakeServer(log_text="one\ntwo\nthree\n")
    out = io.StringIO()
    assert run_call(Mcp(server, Path("/listeners")), ["console_log", "lines=2", "grep=t"], out) == 0
    assert out.getvalue() == "two\nthree\n"


def test_command_line_values_read_as_json_when_they_can_and_as_text_otherwise():
    server = FakeServer()
    run_call(Mcp(server, Path("/listeners")), ["lua_run", "code=return {1, 2}", "instance=2"], io.StringIO())
    assert server.calls == [("lua", Realm.SERVER, "return {1, 2}", 2)]


def test_a_failed_command_line_call_still_prints_why_and_exits_1():
    server = FakeServer({"bp_clear": OpFailed("no breakpoint 9")})
    out = io.StringIO()
    assert run_call(Mcp(server, Path("/listeners")), ["breakpoint_clear", "id=9"], out) == 1
    assert out.getvalue() == "no breakpoint 9\n"


def test_a_string_property_stays_text_even_when_it_reads_as_a_number():
    server = FakeServer()
    run_call(Mcp(server, Path("/listeners")), ["lua_run", "code=42"], io.StringIO())
    assert server.calls == [("lua", Realm.SERVER, "42", 1)]


def test_an_argument_without_a_value_is_refused():
    with pytest.raises(SystemExit):
        run_call(Mcp(FakeServer(), Path("/listeners")), ["console_log", "lines"], io.StringIO())
