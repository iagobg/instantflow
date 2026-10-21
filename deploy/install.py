"""Prepare Instantflow files in an existing private oracle-caddy directory.

Usage: python3 deploy/install.py /path/to/oracle-caddy
Does not start containers, reload Caddy, or change shared configuration.
"""
import os
import pathlib
import secrets
import shutil
import sys


def install(target):
    target = pathlib.Path(target).resolve()
    for name in ("compose.yml", "Caddyfile"):
        if not (target / name).is_file():
            raise ValueError("Expected an existing oracle-caddy directory with " + name)
    source = pathlib.Path(__file__).with_name("oracle-caddy")
    configs = ("projects/instantflow.compose.yml", "caddy-sites/instantflow.caddy")
    # Refuse conflicting files before creating credentials or copying anything.
    for name in configs:
        existing = target / name
        if existing.exists() and existing.read_bytes() != (source / name).read_bytes():
            raise ValueError("Existing configuration differs; review it before updating: " + name)
    names = ("instantflow.env", "instantflow.operator.env", "instantflow.db.env")
    present = [name for name in names if (target / name).exists()]
    if present and len(present) != len(names):
        raise ValueError("Partial existing environment files; reconcile them before installing")
    ignore = target / ".gitignore"
    ignored = ignore.read_text() if ignore.exists() else ""
    rules = ("instantflow.env", "instantflow.operator.env", "instantflow.db.env",
             "instantflow.image.env", "backups/instantflow/")
    missing = [rule for rule in rules if rule not in ignored.splitlines()]
    if missing:
        ignore.write_text(ignored.rstrip() + "\n" + "\n".join(missing) + "\n")
    if not present:
        replacements = {
            "REPLACE_OPERATOR_PASSWORD": secrets.token_hex(32),
            "REPLACE_RUNTIME_PASSWORD": secrets.token_hex(32),
            "REPLACE_WITH_AT_LEAST_64_RANDOM_CHARACTERS": secrets.token_hex(64),
        }
        for name in names:
            text = (source / (name + ".example")).read_text()
            for key, value in replacements.items():
                text = text.replace(key, value)
            descriptor = os.open(target / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as output:
                output.write(text)
    for name in configs:
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, destination)
    for name in names:
        (target / name).chmod(0o600)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    install(sys.argv[1])
    print("Instantflow configuration prepared; no services started and no secrets printed.")
