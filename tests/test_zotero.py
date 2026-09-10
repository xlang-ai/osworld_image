"""Offline regressions for both Zotero layouts and initialization failures."""

import importlib.util
import json
import os
from pathlib import Path
import pwd
import sqlite3
import subprocess
from types import SimpleNamespace
from unittest.mock import Mock
import urllib.error

import pytest

ROOT = Path(__file__).resolve().parents[1]
FILES = ROOT / "ansible/roles/zotero/files"
CONFIGURE = FILES / "configure-zotero-prefs.sh"
SPEC = importlib.util.spec_from_file_location(
    "initialize_zotero", FILES / "initialize-zotero.py"
)
INITIALIZE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INITIALIZE)
USER = pwd.getpwuid(os.getuid()).pw_name


def configure(home, layout="native", check=True):
    return subprocess.run(
        ["bash", str(CONFIGURE), USER, str(home), layout],
        check=check,
        capture_output=True,
        text=True,
    )


def preferences(path):
    values = {}
    for line in path.read_text().splitlines():
        if line.startswith("user_pref("):
            key, value = json.loads("[" + line[len("user_pref(") : -2] + "]")
            assert key not in values, f"Duplicate preference: {key}"
            values[key] = value
    return values


@pytest.mark.parametrize("layout", ["native", "snap"])
@pytest.mark.parametrize("name", ["home", 'home with "quotes" and \\slashes'])
def test_fresh_profile_and_repeat_preserve_preferences(tmp_path, layout, name):
    home = tmp_path / name
    root = home if layout == "native" else home / "snap/zotero-snap/common"
    configure(home, layout)
    profile = root / ".zotero/zotero/osworld.default"
    for filename in ("prefs.js", "user.js"):
        path = profile / filename
        with path.open("a") as stream:
            stream.write('user_pref("unrelated.preference", "keep me");\n')
            stream.write('user_pref("extensions.zotero.httpServer.enabled", false);\n')
    configure(home, layout)
    before = {p: p.read_bytes() for p in profile.iterdir()}
    configure(home, layout)
    assert before == {p: p.read_bytes() for p in profile.iterdir()}
    for filename in ("prefs.js", "user.js"):
        values = preferences(profile / filename)
        assert values["unrelated.preference"] == "keep me"
        assert values["extensions.zotero.dataDir"] == str(root / "Zotero")
        for key in ("httpServer.enabled", "httpServer.localAPI.enabled", "useDataDir"):
            assert values[f"extensions.zotero.{key}"] is True
        assert values["extensions.zotero.firstRun2"] is False
        assert values["extensions.zoteroOpenOfficeIntegration.skipInstallation"] is True
    assert (root / "Zotero").stat().st_uid == os.getuid()


@pytest.mark.parametrize("layout", ["native", "snap"])
def test_existing_relative_and_absolute_profiles_keep_library(tmp_path, layout):
    home = tmp_path / "home"
    root = home if layout == "native" else home / "snap/zotero-snap/common"
    profile_root = root / ".zotero/zotero"
    profile_root.mkdir(parents=True)
    absolute = tmp_path / "external-profile"
    ini = (
        "[General]\nStartWithLastProfile=1\n"
        "[Profile0]\nName=original\nIsRelative=1\nPath=original.default\nDefault=1\n"
        f"[Profile1]\nName=absolute\nIsRelative=0\nPath={absolute}\n"
    )
    (profile_root / "profiles.ini").write_text(ini)
    data = root / "Zotero"
    data.mkdir()
    (data / "zotero.sqlite").write_bytes(b"existing library must remain untouched")
    configure(home, layout)
    assert (profile_root / "profiles.ini").read_text() == ini
    for profile in (profile_root / "original.default", absolute):
        assert preferences(profile / "prefs.js")["extensions.zotero.httpServer.enabled"]
    assert (
        data / "zotero.sqlite"
    ).read_bytes() == b"existing library must remain untouched"


def test_native_and_snap_libraries_are_separate(tmp_path):
    configure(tmp_path, "native")
    configure(tmp_path, "snap")
    roots = [tmp_path, tmp_path / "snap/zotero-snap/common"]
    for root in roots:
        values = preferences(root / ".zotero/zotero/osworld.default/user.js")
        assert values["extensions.zotero.dataDir"] == str(root / "Zotero")
    assert not (roots[1] / "Zotero").is_symlink()


def test_invalid_layout_fails_before_creating_files(tmp_path):
    result = configure(tmp_path, "typo", check=False)
    assert result.returncode == 2
    assert "Unknown Zotero layout" in result.stderr
    assert not list(tmp_path.iterdir())


def test_database_summary_requires_real_zotero_schema(tmp_path):
    database = tmp_path / "zotero.sqlite"
    with pytest.raises(sqlite3.OperationalError):
        INITIALIZE.database_summary(database)
    assert not database.exists()
    with sqlite3.connect(database) as connection:
        connection.execute("create table unrelated (id integer)")
    with pytest.raises(sqlite3.OperationalError):
        INITIALIZE.database_summary(database)
    with sqlite3.connect(database) as connection:
        for table in ("items", "collections", "libraries", "version"):
            connection.execute(f"create table {table} (id integer)")
            connection.execute(f"insert into {table} values (1)")
    assert INITIALIZE.database_summary(database) == dict.fromkeys(
        ["items", "collections", "libraries", "version"], 1
    )


def test_initializer_rejects_an_existing_api(monkeypatch):
    monkeypatch.setattr(INITIALIZE, "read_api", lambda: [])
    popen = Mock()
    monkeypatch.setattr(INITIALIZE.subprocess, "Popen", popen)
    with pytest.raises(RuntimeError, match="Close the existing Zotero"):
        INITIALIZE.initialize(USER, "snap", 1, ":99")
    popen.assert_not_called()


@pytest.mark.parametrize("exits_early", [False, True])
def test_initializer_failure_terminates_only_its_process_group(
    monkeypatch, exits_early
):
    monkeypatch.setattr(
        INITIALIZE, "read_api", Mock(side_effect=urllib.error.URLError("offline"))
    )
    process = Mock(pid=99999, returncode=1)
    process.poll.return_value = 1 if exits_early else None
    popen = Mock(return_value=process)
    monkeypatch.setattr(INITIALIZE.subprocess, "Popen", popen)
    kill = Mock()
    monkeypatch.setattr(INITIALIZE.os, "killpg", kill)
    with pytest.raises(
        RuntimeError, match="exited during startup" if exits_early else "within 0s"
    ):
        INITIALIZE.initialize(USER, "snap", 1 if exits_early else 0, ":99")
    assert popen.call_args.kwargs["start_new_session"] is True
    kill.assert_called_once_with(99999, INITIALIZE.signal.SIGTERM)
    process.wait.assert_called_once_with(timeout=20)


def test_initializer_checks_sqlite_after_application_releases_lock(
    tmp_path, monkeypatch
):
    database = tmp_path / "Zotero/zotero.sqlite"
    database.parent.mkdir()
    connection = sqlite3.connect(database)
    for table in ("items", "collections", "libraries", "version"):
        connection.execute(f"create table {table} (id integer)")
    connection.commit()
    connection.execute("PRAGMA locking_mode=EXCLUSIVE")
    connection.execute("BEGIN EXCLUSIVE")
    monkeypatch.setattr(
        INITIALIZE.pwd,
        "getpwnam",
        lambda _: SimpleNamespace(
            pw_dir=str(tmp_path),
            pw_uid=os.getuid(),
        ),
    )
    monkeypatch.setattr(
        INITIALIZE, "read_api", Mock(side_effect=[urllib.error.URLError("closed"), []])
    )
    monkeypatch.setattr(INITIALIZE, "process_has_database", lambda *_: True)
    process = Mock(pid=99999)
    process.poll.return_value = None
    process.wait.side_effect = lambda **_: connection.close()
    monkeypatch.setattr(INITIALIZE.subprocess, "Popen", Mock(return_value=process))
    monkeypatch.setattr(INITIALIZE.os, "killpg", Mock())
    try:
        result = INITIALIZE.initialize(USER, "native", 1, ":99")
        assert result["database"] == str(database)
        assert result["tables"]["items"] == 0
    finally:
        connection.close()
