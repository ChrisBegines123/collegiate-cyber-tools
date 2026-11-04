"""
Tests for ../get_password.py.

get_password.py has no OS/account dependency, so these tests exercise it
against real files written under tmp_path and only mock the
master-password prompt (getpass.getpass).

Run with:
    pytest linux/common/test/test_get_password.py
"""
import base64
import os
import sys
import time

import pytest

import get_password as gp
import rotate_passwords as rp

MASTER_PASSWORD = "correct horse battery"


def write_passwords_file(path, master=MASTER_PASSWORD, users=None):
    users = users if users is not None else {"alice": "Sup3rSecret!!", "bob": "AnotherOne99$"}
    salt = b"0123456789abcdef"
    enc_key, mac_key = rp.derive_keys(master, salt)
    lines = [f"salt,{base64.b64encode(salt).decode()}", "username,password"]
    for name, pw in users.items():
        lines.append(f"{name},{rp.encrypt(enc_key, mac_key, pw)}")
    path.write_text("\n".join(lines) + "\n")


@pytest.fixture(autouse=True)
def mock_master_password(monkeypatch):
    monkeypatch.setattr(gp.getpass, "getpass", lambda prompt="": MASTER_PASSWORD)


@pytest.fixture(autouse=True)
def run_in_tmp_path(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    return tmp_path


class TestLocatingThePasswordsFile:
    def test_uses_the_file_flag_when_given(self, tmp_path, monkeypatch, capsys):
        path = tmp_path / "custom.csv"
        write_passwords_file(path, users={"alice": "Sup3rSecret!!"})
        monkeypatch.setattr(sys, "argv", ["get_password.py", "--file", str(path)])

        assert gp.main() == 0
        assert "alice" in capsys.readouterr().out

    def test_picks_the_newest_passwords_file_in_the_current_directory(self, tmp_path, monkeypatch, capsys):
        older = tmp_path / "passwords_20200101_000000.csv"
        newer = tmp_path / "passwords_20300101_000000.csv"
        write_passwords_file(older, users={"alice": "OldPassword1!"})
        write_passwords_file(newer, users={"alice": "NewPassword1!"})
        now = time.time()
        os.utime(older, (now - 86400, now - 86400))
        os.utime(newer, (now, now))
        monkeypatch.setattr(sys, "argv", ["get_password.py"])

        assert gp.main() == 0
        assert "NewPassword1!" in capsys.readouterr().out

    def test_errors_when_no_passwords_file_exists_and_no_file_flag_given(self, monkeypatch, capsys):
        monkeypatch.setattr(sys, "argv", ["get_password.py"])

        assert gp.main() == 1
        assert "Could not find a passwords_*.csv file" in capsys.readouterr().err

    def test_errors_when_the_given_file_path_does_not_exist(self, tmp_path, monkeypatch, capsys):
        monkeypatch.setattr(sys, "argv", ["get_password.py", "--file", str(tmp_path / "missing.csv")])

        assert gp.main() == 1
        assert "Could not find" in capsys.readouterr().err

    def test_errors_when_the_file_is_missing_the_salt_line(self, tmp_path, monkeypatch, capsys):
        path = tmp_path / "malformed.csv"
        path.write_text("username,password\nalice,notarealcipher\n")
        monkeypatch.setattr(sys, "argv", ["get_password.py", "--file", str(path)])

        assert gp.main() == 1
        assert "missing salt line" in capsys.readouterr().err


class TestDecryptingWithTheCorrectMasterPassword:
    def test_returns_every_user_with_their_decrypted_password(self, tmp_path, monkeypatch, capsys):
        path = tmp_path / "all.csv"
        write_passwords_file(path, users={"alice": "Sup3rSecret!!", "bob": "AnotherOne99$"})
        monkeypatch.setattr(sys, "argv", ["get_password.py", "--file", str(path)])

        assert gp.main() == 0
        out = capsys.readouterr().out
        assert "Sup3rSecret!!" in out
        assert "AnotherOne99$" in out

    def test_filters_to_the_requested_user(self, tmp_path, monkeypatch, capsys):
        path = tmp_path / "filtered.csv"
        write_passwords_file(path, users={"alice": "Sup3rSecret!!", "bob": "AnotherOne99$"})
        monkeypatch.setattr(sys, "argv", ["get_password.py", "--file", str(path), "--user", "alice"])

        assert gp.main() == 0
        out = capsys.readouterr().out
        assert "Sup3rSecret!!" in out
        assert "AnotherOne99$" not in out

    def test_errors_when_the_requested_user_has_no_entry(self, tmp_path, monkeypatch, capsys):
        path = tmp_path / "filtered2.csv"
        write_passwords_file(path, users={"alice": "Sup3rSecret!!"})
        monkeypatch.setattr(sys, "argv", ["get_password.py", "--file", str(path), "--user", "nobody"])

        assert gp.main() == 1
        assert "No entry for user 'nobody'" in capsys.readouterr().err


class TestDecryptingWithTheWrongMasterPassword:
    def test_emits_a_per_entry_error_and_no_password(self, tmp_path, monkeypatch, capsys):
        path = tmp_path / "wrong.csv"
        write_passwords_file(path, users={"alice": "Sup3rSecret!!", "bob": "AnotherOne99$"})
        monkeypatch.setattr(sys, "argv", ["get_password.py", "--file", str(path)])
        monkeypatch.setattr(gp.getpass, "getpass", lambda prompt="": "wrong password")

        assert gp.main() == 0
        captured = capsys.readouterr()
        assert captured.out == ""
        assert captured.err.count("wrong master password, or the file is corrupt") == 2


class TestTheMasterPasswordPrompt:
    def test_is_read_via_getpass_so_it_is_not_echoed(self, tmp_path, monkeypatch):
        path = tmp_path / "prompt.csv"
        write_passwords_file(path, users={"alice": "Sup3rSecret!!"})
        monkeypatch.setattr(sys, "argv", ["get_password.py", "--file", str(path)])
        calls = []
        monkeypatch.setattr(gp.getpass, "getpass", lambda prompt="": calls.append(prompt) or MASTER_PASSWORD)

        gp.main()

        assert len(calls) == 1
