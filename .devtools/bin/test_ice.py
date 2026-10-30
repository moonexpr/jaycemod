"""ice.py decrypts what Source encrypts with IceKey(0) (Thin-ICE, 8 rounds):
CS:S's weapon scripts (scripts/*.ctx). Checked against ICE's published test
vector, and both ways round, with a tail shorter than a block left as it is."""
import pytest

from ice import IceKey, IceError, decrypt_file

KEY = bytes.fromhex("deadbeef01234567")
PLAIN = bytes.fromhex("fedcba9876543210")
CIPHER = bytes.fromhex("de240d83a00a9cc0")


def test_thin_ice_matches_the_published_vector():
    assert IceKey(KEY).encrypt_block(PLAIN) == CIPHER


def test_a_block_decrypts_back():
    assert IceKey(KEY).decrypt_block(CIPHER) == PLAIN


def test_a_file_decrypts_whole_blocks_and_keeps_its_tail():
    key = IceKey(b"d7NSuLq2")
    text = b"WeaponData\n{\n\t\"MaxPlayerSpeed\" \"221\"\n}\n"
    whole = len(text) - len(text) % 8
    encrypted = b"".join(key.encrypt_block(text[i:i + 8]) for i in range(0, whole, 8)) + text[whole:]
    assert decrypt_file(encrypted, b"d7NSuLq2") == text


def test_a_key_of_the_wrong_length_is_refused():
    with pytest.raises(IceError):
        IceKey(b"short")
