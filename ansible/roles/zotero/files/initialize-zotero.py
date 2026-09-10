#!/usr/bin/env python3
"""Start the installed Zotero, verify its task database, and close it cleanly."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import pwd
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def database_summary(database: Path) -> dict[str, int]:
    with closing(
        sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)
    ) as connection:
        if connection.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise RuntimeError("Zotero database failed quick_check")
        return {
            table: connection.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
            for table in ("items", "collections", "libraries", "version")
        }


def process_has_database(process_group: int, database: Path) -> bool:
    for process in Path("/proc").iterdir():
        if not process.name.isdigit():
            continue
        try:
            if os.getpgid(int(process.name)) != process_group:
                continue
            for descriptor in (process / "fd").iterdir():
                if descriptor.resolve() == database.resolve():
                    return True
        except (OSError, ProcessLookupError):
            continue
    return False


def read_api() -> list[dict]:
    request = urllib.request.Request(
        "http://127.0.0.1:23119/api/users/0/items?limit=1",
        headers={"Zotero-API-Version": "3"},
    )
    # Local verification must not be routed through an HTTP proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=2) as response:
        items = json.load(response)
    if not isinstance(items, list):
        raise RuntimeError("Zotero local API did not return an item list")
    return items


def initialize(
    user: str, layout: str, timeout: int, display: str | None = None
) -> dict[str, object]:
    account = pwd.getpwnam(user)
    user_home = Path(account.pw_dir)
    zotero_home = (
        user_home / "snap/zotero-snap/common" if layout == "snap" else user_home
    )
    database = zotero_home / "Zotero/zotero.sqlite"
    if not display:
        display = os.environ.get("DISPLAY")
    if not display:
        displays = sorted(Path("/tmp/.X11-unix").glob("X*"))
        if not displays:
            raise RuntimeError("Zotero initialization requires a running X11 display")
        display = ":" + displays[0].name[1:]

    try:
        read_api()
    except (OSError, urllib.error.URLError):
        pass
    else:
        raise RuntimeError("Close the existing Zotero before initializing the image")

    runtime = Path(f"/run/user/{account.pw_uid}")
    environment = {
        "HOME": str(user_home),
        "USER": user,
        "LOGNAME": user,
        "DISPLAY": display,
        "XAUTHORITY": str(user_home / ".Xauthority"),
        "XDG_RUNTIME_DIR": str(runtime),
        "GDK_BACKEND": "x11",
    }
    command = ["snap", "run", "zotero-snap"] if layout == "snap" else ["zotero"]
    if (runtime / "bus").exists():
        environment["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={runtime}/bus"
    else:
        command = ["dbus-run-session", "--", *command]
    command = [
        "env",
        "-u",
        "DBUS_SESSION_BUS_ADDRESS",
        *(f"{key}={value}" for key, value in environment.items()),
        *command,
    ]
    if os.geteuid() != account.pw_uid:
        command = ["runuser", "-u", user, "--", *command]

    with tempfile.TemporaryFile(mode="w+") as log:
        process = subprocess.Popen(
            command, stdout=log, stderr=log, start_new_session=True
        )
        try:
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(
                        f"Zotero exited during startup ({process.returncode})"
                    )
                try:
                    read_api()
                    if process_has_database(process.pid, database):
                        break
                except (OSError, urllib.error.URLError, sqlite3.Error):
                    pass
                time.sleep(0.5)
            else:
                raise RuntimeError(
                    f"Zotero did not open {database} and its local API within {timeout}s"
                )
        except Exception as error:
            log.seek(0)
            raise RuntimeError(
                f"{error}\nZotero output:\n{log.read()[-8000:]}"
            ) from error
        finally:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
                raise RuntimeError("Zotero did not stop within 20s")
    # Zotero holds an exclusive SQLite lock while running. Check its schema
    # after shutdown; checking it during startup would falsely time out.
    deadline = time.monotonic() + 20
    while True:
        try:
            summary = database_summary(database)
            break
        except sqlite3.OperationalError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.5)
    return {"layout": layout, "database": str(database), "tables": summary}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("user")
    parser.add_argument("--layout", choices=("snap", "native"), default="snap")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--display")
    args = parser.parse_args()
    # Inspect /proc as the application owner, also in containers whose root
    # lacks CAP_SYS_PTRACE. Do not weaken the container's capability set.
    if os.geteuid() != pwd.getpwnam(args.user).pw_uid:
        os.execvp(
            "runuser",
            [
                "runuser",
                "-u",
                args.user,
                "--",
                sys.executable,
                str(Path(__file__).resolve()),
                *sys.argv[1:],
            ],
        )
    print(
        json.dumps(
            initialize(args.user, args.layout, args.timeout, args.display),
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
