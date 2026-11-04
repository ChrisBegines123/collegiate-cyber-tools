#!/usr/bin/env python3
"""get_password.py

Decrypts the passwords_*.csv file written by rotate_passwords.py
using the master password supplied at runtime.

Usage:
    ./get_password.py [--user USERNAME] [--file FILE]

If --file is omitted, the newest passwords_*.csv in the current
directory is used.
"""
import argparse
import base64
import getpass
import glob
import hashlib
import hmac
import os
import sys

KDF_ITERATIONS = 600_000


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


def decrypt(enc_key: bytes, mac_key: bytes, blob: str) -> str:
    raw = base64.b64decode(blob)
    nonce, tag, ciphertext = raw[:16], raw[16:48], raw[48:]
    expected = hmac.new(mac_key, nonce + ciphertext, hashlib.sha256).digest()
    if not hmac.compare_digest(tag, expected):
        raise ValueError("authentication failed")
    data = bytes(a ^ b for a, b in zip(ciphertext, keystream(enc_key, nonce, len(ciphertext))))
    return data.decode()


def find_latest_passwords_file() -> str | None:
    candidates = glob.glob("passwords_*.csv")
    if not candidates:
        return None
    return max(candidates, key=os.path.getmtime)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user", "-u", help="only show the entry for this username")
    parser.add_argument("--file", "-f", help="passwords CSV to read (default: newest passwords_*.csv in cwd)")
    args = parser.parse_args()

    file_path = args.file or find_latest_passwords_file()
    if not file_path or not os.path.isfile(file_path):
        print(
            "Could not find a passwords_*.csv file in the current directory, "
            "use --file to look somewhere else",
            file=sys.stderr,
        )
        return 1

    lines = [line.rstrip("\n") for line in open(file_path)]
    if not lines or not lines[0].startswith("salt,"):
        print(f"{file_path} does not look like a valid passwords file (missing salt line)", file=sys.stderr)
        return 1
    salt = base64.b64decode(lines[0].split(",", 1)[1])

    master = getpass.getpass("Enter master password: ")
    enc_key, mac_key = derive_keys(master, salt)
    del master

    records = [line for line in lines[2:] if line]
    if args.user:
        records = [line for line in records if line.split(",", 1)[0] == args.user]
        if not records:
            print(f"No entry for user '{args.user}' in {file_path}", file=sys.stderr)
            return 1

    results = []
    for line in records:
        username, cipher = line.split(",", 1)
        try:
            results.append((username, decrypt(enc_key, mac_key, cipher)))
        except Exception:
            print(
                f"Failed to decrypt entry for {username}: wrong master password, or the file is corrupt",
                file=sys.stderr,
            )

    if results:
        width = max(len(u) for u, _ in results)
        print(f"{'Username'.ljust(width)}  Password")
        for username, password in results:
            print(f"{username.ljust(width)}  {password}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
