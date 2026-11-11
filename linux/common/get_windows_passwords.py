#!/usr/bin/env python3
"""get_windows_passwords.py

Decrypts the passwords_*.csv file written by windows/Rotate-Passwords.ps1
using the master password supplied at runtime, and writes a CSV of
username,password (plaintext) to stdout or to --output.

Usage:
    ./get_windows_passwords.py [--user USERNAME] [--file FILE] [--output OUT.csv]

If --file is omitted, the newest passwords_*.csv in the current
directory is used.

Requires the `cryptography` package (pip install cryptography) for AES.
"""
import argparse
import base64
import csv
import getpass
import glob
import hashlib
import os
import sys

try:
    from cryptography.hazmat.primitives import padding
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
except ImportError:
    print("This script needs the 'cryptography' package: pip install cryptography", file=sys.stderr)
    sys.exit(1)

KDF_ITERATIONS = 600_000

# ConvertFrom-SecureString -Key prefixes its output with this constant,
# followed by base64(UTF-16LE("2|<base64 IV>|<hex AES-CBC ciphertext>")).
SECURESTRING_HEADER = "76492d1116743f0423413b16050a5345"


def derive_key(master: str, salt: bytes) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", master.encode("utf-8"), salt, KDF_ITERATIONS, dklen=32)


def decrypt(key: bytes, blob: str) -> str:
    if not blob.startswith(SECURESTRING_HEADER):
        raise ValueError("not a key-encrypted SecureString")
    text = base64.b64decode(blob[len(SECURESTRING_HEADER):]).decode("utf-16-le")
    _version, iv_b64, cipher_hex = text.split("|")
    iv = base64.b64decode(iv_b64)
    ciphertext = bytes.fromhex(cipher_hex)

    decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    padded = decryptor.update(ciphertext) + decryptor.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    plain = unpadder.update(padded) + unpadder.finalize()
    return plain.decode("utf-16-le")


def find_latest_passwords_file() -> str | None:
    candidates = glob.glob("passwords_*.csv")
    if not candidates:
        return None
    return max(candidates, key=os.path.getmtime)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user", "-u", help="only output the entry for this username")
    parser.add_argument("--file", "-f", help="passwords CSV to read (default: newest passwords_*.csv in cwd)")
    parser.add_argument("--output", "-o", help="write the decrypted CSV here instead of stdout")
    args = parser.parse_args()

    file_path = args.file or find_latest_passwords_file()
    if not file_path or not os.path.isfile(file_path):
        print(
            "Could not find a passwords_*.csv file in the current directory, "
            "use --file to look somewhere else",
            file=sys.stderr,
        )
        return 1

    with open(file_path, encoding="utf-8-sig") as f:
        lines = [line.strip() for line in f]
    if not lines or not lines[0].startswith("salt,"):
        print(f"{file_path} does not look like a valid passwords file (missing salt line)", file=sys.stderr)
        return 1
    salt = base64.b64decode(lines[0].split(",", 1)[1])

    master = getpass.getpass("Enter master password: ")
    key = derive_key(master, salt)
    del master

    records = [line for line in lines[2:] if line]
    if args.user:
        records = [line for line in records if line.split(",", 1)[0] == args.user]
        if not records:
            print(f"No entry for user '{args.user}' in {file_path}", file=sys.stderr)
            return 1

    results = []
    failed = 0
    for line in records:
        username, cipher = line.split(",", 1)
        try:
            results.append((username, decrypt(key, cipher)))
        except Exception:
            failed += 1
            print(
                f"Failed to decrypt entry for {username}: wrong master password, or the file is corrupt",
                file=sys.stderr,
            )

    out = open(args.output, "w", newline="") if args.output else sys.stdout
    try:
        writer = csv.writer(out, lineterminator="\n")
        writer.writerow(["username", "password"])
        writer.writerows(results)
    finally:
        if args.output:
            out.close()
            os.chmod(args.output, 0o600)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
