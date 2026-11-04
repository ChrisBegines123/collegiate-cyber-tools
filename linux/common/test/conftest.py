import sys
from pathlib import Path

# rotate_passwords.py and get_password.py live one directory up and aren't
# installed as a package, so make them importable by test modules here.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
