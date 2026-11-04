"""
Tests for ../rotate_passwords.py.

rotate_passwords.py is a top-level script, so these tests import it as a
module and mock every external dependency: os.geteuid, pwd.getpwall,
getpass.getpass, and subprocess.run (chpasswd). Nothing here touches a
real account or runs chpasswd for real.

Run with:
    pytest linux/common/test/test_rotate_passwords.py
"""
import base64
import glob
import os
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

import rotate_passwords as rp

MASTER_PASSWORD = "correct horse battery"


def fake_user(name, uid):
    return SimpleNamespace(pw_name=name, pw_uid=uid)


FAKE_USERS = [
    fake_user("root", 0),
    fake_user("daemon", 1),
    fake_user("nobody", 65534),
    fake_user("operator", 1000),  # whoever is running the script
    fake_user("alice", 1001),
    fake_user("bob", 1002),
]


class FakeCompletedProcess:
    def __init__(self, returncode=0, stderr=""):
        self.returncode = returncode
        self.stderr = stderr


@pytest.fixture
def chpasswd_calls(monkeypatch):
    calls = []

    def fake_run(cmd, input, text, capture_output):
        calls.append(input)
        return FakeCompletedProcess()

    monkeypatch.setattr(rp.subprocess, "run", fake_run)
    return calls


@pytest.fixture(autouse=True)
def common_mocks(monkeypatch, tmp_path):
    monkeypatch.setattr(rp, "__file__", str(tmp_path / "rotate_passwords.py"))
    monkeypatch.setattr(rp.os, "geteuid", lambda: 0)
    monkeypatch.setattr(rp.pwd, "getpwall", lambda: FAKE_USERS)
    monkeypatch.setattr(rp.getpass, "getpass", lambda prompt="": MASTER_PASSWORD)
    monkeypatch.setenv("SUDO_USER", "operator")
    monkeypatch.setattr(sys, "argv", ["rotate_passwords.py"])
    return tmp_path


def read_output_file(tmp_path):
    files = sorted(glob.glob(str(tmp_path / "passwords_*.csv")))
    assert files, "no passwords_*.csv file was written"
    return Path(files[-1]).read_text().splitlines()


class TestLocalUsersToRotate:
    def test_excludes_root_nobody_and_the_invoking_user(self, monkeypatch):
        monkeypatch.setenv("SUDO_USER", "operator")
        users = rp.local_users_to_rotate(min_uid=1000, extra_exclude=set())
        assert "root" not in users
        assert "nobody" not in users
        assert "operator" not in users

    def test_excludes_accounts_below_min_uid(self, monkeypatch):
        monkeypatch.setenv("SUDO_USER", "operator")
        users = rp.local_users_to_rotate(min_uid=1000, extra_exclude=set())
        assert "daemon" not in users

    def test_includes_ordinary_human_accounts(self, monkeypatch):
        monkeypatch.setenv("SUDO_USER", "operator")
        users = rp.local_users_to_rotate(min_uid=1000, extra_exclude=set())
        assert set(users) == {"alice", "bob"}

    def test_raising_min_uid_excludes_more_accounts(self, monkeypatch):
        monkeypatch.setenv("SUDO_USER", "operator")
        users = rp.local_users_to_rotate(min_uid=1002, extra_exclude=set())
        assert set(users) == {"bob"}

    def test_extra_exclude_removes_named_users(self, monkeypatch):
        monkeypatch.setenv("SUDO_USER", "operator")
        users = rp.local_users_to_rotate(min_uid=1000, extra_exclude={"bob"})
        assert set(users) == {"alice"}

    def test_falls_back_to_getpass_getuser_without_sudo_user(self, monkeypatch):
        monkeypatch.delenv("SUDO_USER", raising=False)
        monkeypatch.setattr(rp.getpass, "getuser", lambda: "alice")
        users = rp.local_users_to_rotate(min_uid=1000, extra_exclude=set())
        assert "alice" not in users
        assert "bob" in users


class TestNewRandomPassword:
    def test_default_length_is_sixteen(self):
        assert len(rp.new_random_password()) == 16

    def test_custom_length_is_honored(self):
        assert len(rp.new_random_password(24)) == 24

    def test_has_lowercase_uppercase_and_digit(self):
        pw = rp.new_random_password(16)
        assert any(c.islower() for c in pw)
        assert any(c.isupper() for c in pw)
        assert any(c.isdigit() for c in pw)

    def test_only_uses_allowed_characters(self):
        pw = rp.new_random_password(16)
        assert all(c in rp.PASSWORD_CHARS for c in pw)

    def test_retries_until_an_acceptable_password_is_generated(self, monkeypatch):
        # First 16-char draw is all lowercase (no upper/digit) and must be
        # rejected; the second draw is a valid mix and must be returned.
        bad = list("alllowercasepwd!")
        good = list("Ab1cdefghijklmno")
        sequence = iter(bad + good)
        monkeypatch.setattr(rp.secrets, "choice", lambda chars: next(sequence))

        assert rp.new_random_password(16) == "".join(good)


class TestEncryptDecrypt:
    def test_round_trips_with_the_same_key(self):
        salt = b"0" * 16
        enc_key, mac_key = rp.derive_keys(MASTER_PASSWORD, salt)
        blob = rp.encrypt(enc_key, mac_key, "Sup3rSecret!!")

        # decrypt lives in get_password.py; re-derive with the sibling
        # module to prove the two scripts speak the same format.
        import get_password as gp

        plain = gp.decrypt(enc_key, mac_key, blob)
        assert plain == "Sup3rSecret!!"

    def test_fails_to_decrypt_with_the_wrong_key(self):
        salt = b"0" * 16
        enc_key, mac_key = rp.derive_keys(MASTER_PASSWORD, salt)
        blob = rp.encrypt(enc_key, mac_key, "Sup3rSecret!!")

        wrong_enc, wrong_mac = rp.derive_keys("wrong password", salt)

        import get_password as gp

        with pytest.raises(ValueError):
            gp.decrypt(wrong_enc, wrong_mac, blob)


class TestMainAccountSelection:
    def test_resets_ordinary_users(self, chpasswd_calls, common_mocks):
        rp.main()
        users_touched = {c.split(":")[0] for c in chpasswd_calls}
        assert users_touched == {"alice", "bob"}

    def test_never_resets_root_nobody_or_the_invoking_user(self, chpasswd_calls, common_mocks):
        rp.main()
        users_touched = {c.split(":")[0] for c in chpasswd_calls}
        assert "root" not in users_touched
        assert "nobody" not in users_touched
        assert "operator" not in users_touched

    def test_resets_nobody_when_only_protected_accounts_exist(self, chpasswd_calls, common_mocks, monkeypatch):
        monkeypatch.setattr(
            rp.pwd, "getpwall",
            lambda: [fake_user("root", 0), fake_user("operator", 1000)],
        )
        rp.main()
        assert chpasswd_calls == []

    def test_resets_each_user_exactly_once(self, chpasswd_calls, common_mocks):
        rp.main()
        assert len(chpasswd_calls) == 2

    def test_exclude_flag_protects_additional_accounts(self, chpasswd_calls, common_mocks, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["rotate_passwords.py", "--exclude", "bob"])
        rp.main()
        users_touched = {c.split(":")[0] for c in chpasswd_calls}
        assert users_touched == {"alice"}


class TestMainGeneratedPasswords:
    def test_passwords_are_the_requested_length(self, chpasswd_calls, common_mocks, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["rotate_passwords.py", "--length", "20"])
        rp.main()
        for call in chpasswd_calls:
            _, pw = call.rstrip("\n").split(":", 1)
            assert len(pw) == 20

    def test_every_user_gets_a_different_password(self, chpasswd_calls, common_mocks):
        rp.main()
        passwords = [c.rstrip("\n").split(":", 1)[1] for c in chpasswd_calls]
        assert len(set(passwords)) == len(passwords)


class TestMainOutputFile:
    def test_starts_with_a_salt_line_holding_16_bytes_of_base64(self, chpasswd_calls, common_mocks):
        rp.main()
        lines = read_output_file(common_mocks)
        assert lines[0].startswith("salt,")
        salt = base64.b64decode(lines[0].split(",", 1)[1])
        assert len(salt) == 16

    def test_has_a_header_line_then_one_record_per_reset_user(self, chpasswd_calls, common_mocks):
        rp.main()
        lines = read_output_file(common_mocks)
        assert lines[1] == "username,password"
        records = lines[2:]
        assert len(records) == 2
        assert [r.split(",")[0] for r in records] == ["alice", "bob"]

    def test_never_writes_a_plaintext_password_or_master_password(self, chpasswd_calls, common_mocks):
        rp.main()
        lines = read_output_file(common_mocks)
        text = "\n".join(lines)
        for call in chpasswd_calls:
            pw = call.rstrip("\n").split(":", 1)[1]
            assert pw not in text
        assert MASTER_PASSWORD not in text

    def test_can_be_decrypted_with_the_master_password_and_saved_salt(self, chpasswd_calls, common_mocks):
        rp.main()
        lines = read_output_file(common_mocks)
        salt = base64.b64decode(lines[0].split(",", 1)[1])
        enc_key, mac_key = rp.derive_keys(MASTER_PASSWORD, salt)

        plaintexts = {c.split(":")[0]: c.rstrip("\n").split(":", 1)[1] for c in chpasswd_calls}

        import get_password as gp

        for line in lines[2:]:
            user, cipher = line.split(",", 1)
            assert gp.decrypt(enc_key, mac_key, cipher) == plaintexts[user]

    def test_cannot_be_decrypted_with_a_wrong_master_password(self, chpasswd_calls, common_mocks):
        rp.main()
        lines = read_output_file(common_mocks)
        salt = base64.b64decode(lines[0].split(",", 1)[1])
        wrong_enc, wrong_mac = rp.derive_keys("wrong password", salt)

        import get_password as gp

        cipher = lines[2].split(",", 1)[1]
        with pytest.raises(ValueError):
            gp.decrypt(wrong_enc, wrong_mac, cipher)


class TestMainFailures:
    def test_keeps_going_after_one_reset_fails_and_records_only_successes(self, common_mocks, monkeypatch, capsys):
        def fake_run(cmd, input, text, capture_output):
            user = input.split(":")[0]
            if user == "alice":
                return FakeCompletedProcess(returncode=1, stderr="password does not meet policy")
            return FakeCompletedProcess()

        monkeypatch.setattr(rp.subprocess, "run", fake_run)

        rp.main()

        lines = read_output_file(common_mocks)
        records = lines[2:]
        assert len(records) == 1
        assert records[0].startswith("bob,")
        assert "alice" in capsys.readouterr().err

    def test_rejects_running_as_non_root_before_touching_anything(self, common_mocks, monkeypatch):
        monkeypatch.setattr(rp.os, "geteuid", lambda: 1000)
        getpass_calls = []
        monkeypatch.setattr(rp.getpass, "getpass", lambda prompt="": getpass_calls.append(1))

        def fail_run(*a, **k):
            raise AssertionError("chpasswd should never be invoked")

        monkeypatch.setattr(rp.subprocess, "run", fail_run)

        exit_code = rp.main()

        assert exit_code == 1
        assert getpass_calls == []
        assert glob.glob(str(common_mocks / "passwords_*.csv")) == []
