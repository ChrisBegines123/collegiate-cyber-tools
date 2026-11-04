#!/usr/bin/env python3
"""rotate_passwords.py

Resets the password of every local, human user account on the box to a
fresh random value and records the new passwords in a CSV file, encrypted
with a master password you supply at runtime.

Only the standard library is used (hashlib/hmac for the KDF and a
keystream cipher, no third-party crypto package required), so this runs
on any Python 3 install with no pip install needed.

Usage:
    sudo ./rotate_passwords.py [--min-uid UID] [--length N]

Must be run as root (needed to reset other users' passwords via
chpasswd). Never touches root, nobody, or the account that invoked the
script (via $SUDO_USER).

Output: passwords_<timestamp>.csv next to this script, same format as
Rotate-Passwords.ps1's output: a "salt,<base64>" line, a header line,
then one "username,<encrypted blob>" line per account. Read it back with
get_password.py.
"""
import argparse
import base64
import getpass
import hashlib
import hmac
import os
import pwd
import secrets
import string
import subprocess
import sys
from datetime import datetime
from pathlib import Path

KDF_ITERATIONS = 600_000
ALWAYS_EXCLUDE = {"root", "nobody"}
PASSWORD_CHARS = string.ascii_letters + string.digits + "!@#$%^*()_+=?.,:-"


def derive_keys(master: str, salt: bytes) -> tuple[bytes, bytes]:
    derived = hashlib.pbkdf2_hmac("sha256", master.encode(), salt, KDF_ITERATIONS, dklen=64)
    return derived[:32], derived[32:]


def keystream(key: bytes, nonce: bytes, length: int) -> bytes:
    out = b""
    counter = 0
    while len(out) < length:
        out += hmac.new(key, nonce + counter.to_bytes(4, "big"), hashlib.sha256).digest()
        counter += 1
    return out[:length]


def encrypt(enc_key: bytes, mac_key: bytes, plaintext: str) -> str:
    nonce = secrets.token_bytes(16)
    data = plaintext.encode()
    ciphertext = bytes(a ^ b for a, b in zip(data, keystream(enc_key, nonce, len(data))))
    tag = hmac.new(mac_key, nonce + ciphertext, hashlib.sha256).digest()
    return base64.b64encode(nonce + tag + ciphertext).decode()


def new_random_password(length: int = 16) -> str:
    while True:
        pw = "".join(secrets.choice(PASSWORD_CHARS) for _ in range(length))
        if (
            any(c.islower() for c in pw)
            and any(c.isupper() for c in pw)
            and any(c.isdigit() for c in pw)
        ):
            return pw


def local_users_to_rotate(min_uid: int, extra_exclude: set[str]) -> list[str]:
    self_user = os.environ.get("SUDO_USER") or getpass.getuser()
    exclude = ALWAYS_EXCLUDE | extra_exclude | {self_user}
    return [
        entry.pw_name
        for entry in pwd.getpwall()
        if entry.pw_uid >= min_uid and entry.pw_name not in exclude
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--min-uid", type=int, default=1000, help="minimum UID treated as a human account (default 1000)")
    parser.add_argument("--length", type=int, default=16, help="generated password length (default 16)")
    parser.add_argument("--exclude", action="append", default=[], help="additional username to never rotate (repeatable)")
    args = parser.parse_args()

    if os.geteuid() != 0:
        print("rotate_passwords.py must be run as root", file=sys.stderr)
        return 1

    out_file = Path(__file__).resolve().parent / f"passwords_{datetime.now():%Y%m%d_%H%M%S}.csv"

    master = getpass.getpass("Enter master password: ")
    salt = secrets.token_bytes(16)
    enc_key, mac_key = derive_keys(master, salt)
    del master

    out_file.write_text(f"salt,{base64.b64encode(salt).decode()}\n")
    with out_file.open("a") as f:
        f.write("username,password\n")

        for user in local_users_to_rotate(args.min_uid, set(args.exclude)):
            pw = new_random_password(args.length)
            result = subprocess.run(
                ["chpasswd"], input=f"{user}:{pw}\n", text=True, capture_output=True
            )
            if result.returncode != 0:
                print(
                    f"Something went wrong when attempting to change the password for {user}: "
                    f"{result.stderr.strip()}",
                    file=sys.stderr,
                )
                continue
            f.write(f"{user},{encrypt(enc_key, mac_key, pw)}\n")
            print(f"Password changed for {user}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
