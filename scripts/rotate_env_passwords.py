#!/usr/bin/env python3
"""Rotate secrets defined in the project .env and update running services.

The script will:
  * Generate new random passwords for supported keys inside .env.
  * Apply the new credentials to the corresponding running containers.
  * Persist the updated secrets back into .env (with a timestamped backup).
  * Restart Passbolt so it reconnects with the rotated database password.

Only secrets that can be updated locally are rotated. Remote credentials
such as mailbox.org must still be changed manually after this script runs.
"""

from __future__ import annotations

import base64
import datetime
import secrets
import string
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Optional

REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_PATH = REPO_ROOT / ".env"


class RotationError(RuntimeError):
    """Raised when an individual rotation step fails."""


def random_ascii(length: int = 32) -> str:
    """Return a random password consisting of safe ASCII characters."""
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def random_base64(num_bytes: int = 32) -> str:
    """Return a base64 encoded token suitable for secret keys."""
    token = base64.urlsafe_b64encode(secrets.token_bytes(num_bytes)).decode()
    return token.rstrip("=")


def run(cmd: List[str], *, cwd: Path = REPO_ROOT, input_bytes: Optional[bytes] = None) -> None:
    """Execute a command and raise RotationError on failure."""
    try:
        subprocess.run(cmd, cwd=cwd, check=True, input=input_bytes)
    except subprocess.CalledProcessError as exc:
        raise RotationError(f"Command failed: {' '.join(cmd)}") from exc


def rotate_pihole(new_password: str) -> None:
    """Apply the new Pi-hole admin password supplied via stdin."""
    stdin = f"{new_password}\n{new_password}\n".encode("utf-8")
    run(["docker", "exec", "-i", "pihole", "pihole", "-a", "-p"], input_bytes=stdin)


def rotate_samba(env: Dict[str, str], new_password: str) -> None:
    """Apply the new Samba password for the configured user."""
    samba_user = env.get("SAMBA_USER")
    if not samba_user:
        raise RotationError("SAMBA_USER is missing from .env; cannot rotate Samba password.")

    run(
        [
            "docker",
            "exec",
            "-e",
            f"SMB_USER={samba_user}",
            "-e",
            f"NEW_PASS={new_password}",
            "samba",
            "bash",
            "-lc",
            r'printf "%s\n%s\n" "$NEW_PASS" "$NEW_PASS" | smbpasswd -s "$SMB_USER"',
        ]
    )


def rotate_passbolt_db(env: Dict[str, str], old_password: str, new_password: str) -> None:
    """Update the Passbolt MariaDB user password inside the database."""
    db_user = env.get("MYSQL_USER")
    db_name = env.get("MYSQL_DATABASE")
    if not db_user or not db_name:
        raise RotationError("MYSQL_USER or MYSQL_DATABASE missing from .env; cannot rotate Passbolt DB password.")

    sql = "ALTER USER CURRENT_USER() IDENTIFIED BY '{pwd}'; FLUSH PRIVILEGES;".format(pwd=new_password)
    run(
        [
            "docker",
            "exec",
            "passbolt-db",
            "mysql",
            f"-u{db_user}",
            f"-p{old_password}",
            "-D",
            db_name,
            "-e",
            sql,
        ]
    )


def restart_passbolt() -> None:
    """Restart the Passbolt application container so it reads the new password."""
    run(
        [
            "docker",
            "compose",
            "--env-file",
            str(ENV_PATH),
            "-f",
            "docker-compose.passbolt.yaml",
            "up",
            "-d",
            "passbolt",
        ]
    )


@dataclass
class SecretConfig:
    generator: Callable[[], str]
    apply: Optional[Callable[[Dict[str, str], str, str], None]] = None
    post_note: Optional[str] = None


SECRET_CONFIG: Dict[str, SecretConfig] = {
    "PIHOLE_PASSWORD": SecretConfig(generator=random_ascii, apply=lambda env, old, new: rotate_pihole(new)),
    "SAMBA_PASSWORD": SecretConfig(generator=random_ascii, apply=lambda env, old, new: rotate_samba(env, new)),
    "MYSQL_PASSWORD": SecretConfig(generator=random_ascii, apply=lambda env, old, new: rotate_passbolt_db(env, old, new)),
    "MAIL_PW": SecretConfig(
        generator=random_ascii,
        post_note="Passwort auch im Mail-Anbieter (mailbox.org) anpassen!",
    ),
    "PAPERLESS_SECRET_KEY": SecretConfig(
        generator=random_base64,
        post_note="Paperless-ngx wird bestehende Sessions abmelden.",
    ),
}


def load_env(path: Path) -> tuple[Dict[str, str], List[Dict[str, str]]]:
    """Return env mapping plus a representation of original lines."""
    if not path.exists():
        raise FileNotFoundError(f"{path} does not exist.")

    env: Dict[str, str] = {}
    lines: List[Dict[str, str]] = []

    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#") or "=" not in raw_line:
                lines.append({"type": "raw", "raw": raw_line})
                continue

            key, value = raw_line.split("=", 1)
            value = value.rstrip("\n")
            env[key] = value
            lines.append({"type": "kv", "key": key, "value": value})

    return env, lines


def write_env(path: Path, lines: List[Dict[str, str]], updates: Dict[str, str]) -> None:
    """Persist env lines with applied updates."""
    with path.open("w", encoding="utf-8") as handle:
        for entry in lines:
            if entry["type"] == "kv":
                key = entry["key"]
                value = updates.get(key, entry["value"])
                handle.write(f"{key}={value}\n")
            else:
                handle.write(entry["raw"])


def ensure_docker_available() -> None:
    """Fail fast if docker is not available."""
    try:
        subprocess.run(["docker", "--version"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        raise SystemExit("docker CLI ist nicht verfügbar oder liefert einen Fehler.") from exc


def main() -> int:
    ensure_docker_available()

    env, lines = load_env(ENV_PATH)

    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = ENV_PATH.with_name(f".env.backup-{timestamp}")
    backup_path.write_text(ENV_PATH.read_text(encoding="utf-8"), encoding="utf-8")
    print(f"Backup erstellt: {backup_path}")

    updates: Dict[str, str] = {}
    post_notes: List[str] = []
    rotated_db = False

    for key, config in SECRET_CONFIG.items():
        if key not in env:
            continue

        old_value = env[key]
        new_value = config.generator()
        updates[key] = new_value

        apply_fn = config.apply
        if apply_fn:
            print(f"{key}: aktualisiere laufenden Dienst …")
            try:
                apply_fn(env, old_value, new_value)
            except RotationError as exc:
                print(f"❌ {key} konnte nicht aktualisiert werden: {exc}")
                print("Rollback: ursprüngliche .env wiederhergestellt.")
                ENV_PATH.write_text(backup_path.read_text(encoding="utf-8"), encoding="utf-8")
                return 1
            if key == "MYSQL_PASSWORD":
                rotated_db = True

        if config.post_note:
            post_notes.append(f"{key}: {config.post_note}")

        env[key] = new_value

    if not updates:
        print("Keine zu rotierenden Einträge gefunden.")
        return 0

    write_env(ENV_PATH, lines, updates)
    print(f".env aktualisiert ({len(updates)} Werte geändert).")

    if rotated_db:
        print("Passbolt wird neu gestartet …")
        try:
            restart_passbolt()
        except RotationError as exc:
            print(f"⚠️ Passbolt Neustart fehlgeschlagen: {exc}")
            print("Bitte manuell mit 'docker compose up -d passbolt' nachziehen.")

    print("\nNeue Werte:")
    for key, value in updates.items():
        print(f"  {key}={value}")

    if post_notes:
        print("\nFolgenotizen:")
        for note in post_notes:
            print(f"  - {note}")

    print("\nHinweis: Die ursprüngliche Datei liegt als Backup hier:", backup_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
