"""server_lua.py's framing and replies, against a listener on a free port that
answers as server_root/luadev_socket.lua does."""
import io
import json
import socket
import threading

import pytest

from server_lua import (BridgeDown, NoReply, OpFailed, Realm, Reply, address, call_op, chunk_source, frame, op_frame,
                        parse_reply, run)


def test_a_frame_is_realm_label_and_byte_length_lines_then_the_code():
    assert frame(Realm.SERVER, "print('é')", "server_lua") == b"sv\nserver_lua\n11\nprint('\xc3\xa9')"


def test_a_frame_refuses_a_label_with_a_newline():
    with pytest.raises(ValueError):
        frame(Realm.SERVER, "x", "two\nlines")


def test_a_reply_is_decoded_into_output_returns_error_and_clients():
    reply = parse_reply(b'{"output":["a","b"],"returns":["1"],"error":"boom","clients":2}')
    assert reply == Reply(["a", "b"], ["1"], "boom", 2)


def test_gmods_json_turns_an_empty_list_into_an_object_and_leaves_out_nil():
    assert parse_reply(b'{"output":{},"returns":{}}') == Reply([], [], None, None)


def answering(reply: bytes):
    """A one-shot listener that records the request and sends `reply`."""
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    got = {}

    def serve():
        conn, _ = listener.accept()
        with conn:
            data = b""
            while chunk := conn.recv(4096):
                data += chunk
                if data.count(b"\n") >= 3 and len(data.split(b"\n", 3)[3]) >= int(data.split(b"\n", 3)[2]):
                    break
            got["request"] = data
            conn.sendall(reply)
        listener.close()

    threading.Thread(target=serve, daemon=True).start()
    return listener.getsockname(), got


def test_run_sends_the_frame_and_returns_the_reply():
    address, got = answering(json.dumps({"output": ["gm_construct"], "returns": []}).encode())
    reply = run(Realm.SERVER, "print(game.GetMap())", address, timeout=5)
    assert got["request"] == frame(Realm.SERVER, "print(game.GetMap())", "server_lua")
    assert reply == Reply(["gm_construct"], [], None, None)


def test_run_without_a_listener_is_bridge_down():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        address = s.getsockname()
    with pytest.raises(BridgeDown):
        run(Realm.SERVER, "x", address, timeout=1)


def test_a_connection_closed_without_a_reply_is_no_reply():
    address, _ = answering(b"")
    with pytest.raises(NoReply):
        run(Realm.SERVER, "x", address, timeout=5)


def test_each_server_instance_has_its_own_luadev_address():
    assert address(1) == ("127.0.0.1", 27098)
    assert address(2) == ("127.0.0.1", 27100)


def test_the_chunk_comes_from_the_argument_the_file_or_stdin(tmp_path):
    script = tmp_path / "chunk.lua"
    script.write_text("return 2")
    stdin = io.StringIO("return 3")
    assert chunk_source("return 1", None, stdin) == "return 1"
    assert chunk_source(None, script, stdin) == "return 2"
    assert chunk_source(None, None, stdin) == "return 3", "a heredoc needs no quoting"
    assert chunk_source("-", None, io.StringIO("return 4")) == "return 4"


def test_an_op_frame_names_the_op_and_carries_its_arguments_as_json():
    assert op_frame("bp_set", {"line": 4}) == b'op\nbp_set\n11\n{"line": 4}'


def test_an_op_answers_what_it_returned():
    address, got = answering(json.dumps({"output": [], "returns": [], "result": {"id": 1}}).encode())
    assert call_op("bp_set", {"line": 4}, address, timeout=5) == {"id": 1}
    assert got["request"] == op_frame("bp_set", {"line": 4})


def test_an_op_that_raised_is_op_failed_with_its_message():
    address, _ = answering(json.dumps({"output": [], "returns": [], "error": "no breakpoint 9"}).encode())
    with pytest.raises(OpFailed, match="no breakpoint 9"):
        call_op("bp_clear", {"id": 9}, address, timeout=5)


def test_an_op_that_returned_nothing_answers_none():
    address, _ = answering(json.dumps({"output": [], "returns": []}).encode())
    assert call_op("bp_list", {}, address, timeout=5) is None
