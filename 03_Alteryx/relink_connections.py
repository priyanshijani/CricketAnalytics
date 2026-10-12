"""Points every Alteryx workflow and macro in 03_Alteryx/ at this machine's two database connections.

    python 03_Alteryx\\relink_connections.py            (rewrite the files)
    python 03_Alteryx\\relink_connections.py --check    (report only, change nothing)

Why: Alteryx Designer stores a Data Connection Manager (DCM) connection in each tool by its connection ID, a GUID
created on the machine where the connection was made. Created again on another machine, the same connection gets a
new ID, and every tool would report it missing. This script reads the IDs of the connections created on this machine
(from Designer's local DCM store, read-only) and writes them into the tools that use them. The tools keep their
connection title (CricketSource_DSN / CricketDW_DSN), so the script can be re-run at any time.

Before running it: create the two ODBC DSNs and the two Alteryx connections (07_Docs/deployment.md, steps B5 and B6), and
close Designer. Needs only the Python standard library.
"""
import base64
import glob
import os
import re
import sqlite3
import sys
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
# workflow connection title -> names accepted for the local connection (the DSN name is matched as well)
TARGETS = {
    "CricketSource_DSN": ("CricketSource_DSN", "CricketSource_DB"),
    "CricketDW_DSN": ("CricketDW_DSN", "CricketDW_DB"),
}
TAG = re.compile(r'(<Connection DcmType="ConnectionId" DcmTitle="(?P<title>[^"]+)"[^>]*>)(?P<id>[0-9a-fA-F-]{36})(</Connection>)')


def dcm_store():
    files = sorted(glob.glob(os.path.join(os.environ.get("LOCALAPPDATA", ""), "Alteryx", "Dcm.*.sqlite")))
    if not files:
        sys.exit("[FAIL] No Alteryx DCM store found under %LOCALAPPDATA%\\Alteryx. Is Alteryx Designer installed and has it "
                 "been opened once?")
    return files[-1]


def to_guid(object_id):
    """DCM stores an ID as the 16 UUID bytes in URL-safe base64 without padding (22 characters)."""
    g = uuid.UUID(bytes=base64.urlsafe_b64decode(object_id + "=="))
    if g.version != 4:
        sys.exit(f"[FAIL] Unexpected DCM ID format ({object_id}); relink the connections in Designer instead.")
    return str(g)


def local_connections():
    db = sqlite3.connect(f"file:{dcm_store()}?mode=ro", uri=True)
    rows = db.execute("SELECT c.objectId, c.name, d.name, d.parameters FROM Connections c "
                      "LEFT JOIN DataSources d ON d.objectId = c.dsId").fetchall()
    found = {}
    for title, names in TARGETS.items():
        dsn = title                                        # the connection title equals its DSN name
        hits = [r for r in rows if r[1] in names or dsn in (r[3] or "")]
        if len(hits) != 1:
            listing = ", ".join(sorted(str(r[1]) for r in rows)) or "none"
            sys.exit(f"[FAIL] Expected exactly one Alteryx connection for {title} (named {' or '.join(names)}, using DSN "
                     f"{dsn}); found {len(hits)}. Connections on this machine: {listing}.")
        found[title] = to_guid(hits[0][0])
        print(f"[OK]   {title}: connection '{hits[0][1]}' -> {found[title]}")
    return found


def main():
    check = "--check" in sys.argv
    ids = local_connections()
    files = [f for f in glob.glob(os.path.join(HERE, "**", "*.yxm[dc]"), recursive=True) if "_backup" not in f]
    changed = 0
    for path in files:
        with open(path, "rb") as fh:
            raw = fh.read()
        text = raw.decode("utf-8")
        n = 0

        def swap(m):
            nonlocal n
            new = ids.get(m.group("title"))
            if new is None or m.group("id").lower() == new:
                return m.group(0)
            n += 1
            return m.group(1) + new + m.group(4)

        out = TAG.sub(swap, text)
        unknown = {m.group("title") for m in TAG.finditer(text)} - set(ids)
        if unknown:
            print(f"[WARN] {os.path.relpath(path, HERE)}: connection title(s) not handled: {', '.join(sorted(unknown))}")
        if n:
            changed += 1
            print(f"{'[WOULD]' if check else '[FIX] '} {os.path.relpath(path, HERE)}: {n} connection reference(s)")
            if not check:
                with open(path, "wb") as fh:
                    fh.write(out.encode("utf-8"))
    verb = "need relinking" if check else "relinked"
    print(f"\n{changed} of {len(files)} workflow / macro files {verb}." if changed else
          f"\nAll {len(files)} workflow / macro files already point at this machine's connections.")


if __name__ == "__main__":
    main()
