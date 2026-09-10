# Zotero parity with the August 25 VM image

The Hugging Face [image fix, PR #6](https://huggingface.co/datasets/xlangai/v2-image/discussions/6)
was merged on **2026-08-25**, at commit
`6e16459a2feb5a8f1ed65babcfe7a2a6205d049d`. It installs and initializes
`zotero-snap` for tasks 011, 036 and 062. The builder previously installed
only the native Zotero tarball, so rebuilding the VM did not reproduce this fix.

The published artifact was downloaded, its ZIP checksum verified, and its
`/var/lib/snapd/state.json` and `/snap/zotero-snap/current/meta/snap.yaml`
inspected to establish these pins:

| Component | Value |
| --- | --- |
| Ubuntu ZIP SHA-256 | `14b08aa7ba6c023ecb91d46de8df5de32af4d1d6bd75ea925519caf9677fc8b3` |
| Zotero snap | `9.0.1`, revision `128`, strict confinement |
| Snap SHA-256 | `9d4cd8ab1bcba8bd98e042f7f6b0ee4303f422aa04ab1c3ca100c99ff68e7713` |
| VM launch command | `snap run zotero-snap` |
| VM profile root | `~/snap/zotero-snap/common/.zotero/zotero/` |
| VM task database | `~/snap/zotero-snap/common/Zotero/zotero.sqlite` |
| Native Zotero | `8.0.2`, existing pinned tarball |

The VM package role installs the pinned snap, validates its contents and version,
and holds automatic refreshes. The Zotero role configures the snap profile,
suppresses first-run prompts, enables the local API, and launches Zotero once
as the desktop user to initialize its real database. A working X11 session is
required during provisioning. Existing profiles and libraries are preserved.
Native and snap libraries remain separate to avoid opening a Zotero 9 library
with Zotero 8.

The OSWorld **Docker provider** boots this qcow2 as a full VM and supports snapd.
The separate **Docker XFCE image** built by `docker/update/` has no systemd or
snapd; it keeps native Zotero 8.0.2 and `~/Zotero/`. Tasks that explicitly invoke
`snap run zotero-snap` require the VM target. Native Docker smoke checks verify
the native application and its local API without adding snapd.

## Validation

Offline regression checks:

```bash
python3 -m pytest -q tests/test_zotero.py
ansible-playbook --syntax-check ansible/playbook.yml
ansible-playbook --syntax-check tests/zotero.yml
shellcheck ansible/roles/zotero/files/configure-zotero-prefs.sh \
  scripts/download-provision-assets.sh tests/smoke.sh scripts/smoke-docker-update.sh
```

On a disposable, running OSWorld VM with snapd and X11, run the focused install
and configuration test twice. Use a named inventory host (for example,
`zotero_vm ansible_host=127.0.0.1 ansible_port=2222`) so Ansible's controller
cache checks delegated to `localhost` run on the controller:

```bash
ansible-playbook -i <inventory> tests/zotero.yml
ansible-playbook -i <inventory> tests/zotero.yml
```

For an existing native Docker update image, pass `-e target_platform=docker`.
The native tarball must already be installed. These checks start and stop
Zotero and therefore require it to be closed before running them.

The runtime verifier requires the launched process to open the expected
database and serve an item list through the local API. It then closes the
application, runs SQLite `quick_check`, and checks the core schema. This catches
wrong profile paths, missing installations, startup failures, and empty files
masquerading as initialized databases. SQLite is checked after shutdown because
Zotero holds an exclusive lock while running.

This source update does not change historical benchmark release tags or publish
new VM artifacts. A new artifact release should record its own checksum and
matching benchmark manifest.
