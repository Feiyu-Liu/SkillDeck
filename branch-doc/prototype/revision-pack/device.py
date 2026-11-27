#!/usr/bin/env python3
"""Device side of the Revision Pack prototype (brief P1-P10).

Calls the vendored libgit2 1.9.7 through skills_workspace's private native
ABI (libskills_workspace_native), the same entry points the Workspace uses for
R11 seams 1 and 2. Prototype harness only: not product code, not public API.

Every command prints one JSON object on stdout. Read-only checks that the
native ABI has no entry point for (listing parents) use system Git on the
Store; nothing writes to a Store with system Git.
"""

import argparse
import ctypes
import hashlib
import json
import os
import random
import shutil
import subprocess
import sys
import time

OID = 41
KIND = {
    "initial": 0,
    "upstream": 1,
    "effective-update": 2,
    "local-publish": 3,
    "sync-candidate": 6,
}


def _lib():
    path = os.environ.get("SKILLS_WORKSPACE_NATIVE")
    if not path:
        sys.exit("set SKILLS_WORKSPACE_NATIVE to libskills_workspace_native.so")
    lib = ctypes.CDLL(path)
    i32, ip, cp = ctypes.c_int32, ctypes.c_ssize_t, ctypes.c_char_p
    cpp = ctypes.POINTER(cp)
    u8p = ctypes.POINTER(ctypes.c_uint8)
    sig = {
        "skills_workspace_revision_init": [],
        "skills_workspace_revision_store_create": [cp],
        "skills_workspace_revision_store_open_verify": [cp],
        "skills_workspace_revision_tree_create": [
            cp, cpp, ctypes.POINTER(u8p), ctypes.POINTER(ip),
            ctypes.POINTER(i32), ip, cp, ip],
        "skills_workspace_revision_commit_create_root": [cp, cp, cp, ip],
        "skills_workspace_revision_commit_create": [cp, cp, cpp, ip, i32, cp, ip],
        "skills_workspace_revision_merge_sync": [
            cp, cp, cp, cp, cp, ip, u8p, ip, ctypes.POINTER(ip),
            ctypes.POINTER(ip)],
        "skills_workspace_revision_merge_base": [cp, cp, cp, cp, ip],
        "skills_workspace_revision_export_pack_create": [cp, cp, cpp, ip],
        "skills_workspace_revision_pack_import": [cp, cp, cp, cpp, ip, cp, ip],
        "skills_workspace_revision_tree_list": [cp, cp, u8p, ip, ctypes.POINTER(ip)],
        "skills_workspace_revision_blob_read": [cp, cp, u8p, ip, ctypes.POINTER(ip)],
    }
    for name, args in sig.items():
        fn = getattr(lib, name)
        fn.argtypes = args
        fn.restype = i32
    if lib.skills_workspace_revision_init() != 0:
        sys.exit("native init failed")
    return lib


LIB = None


def native():
    global LIB
    if LIB is None:
        LIB = _lib()
    return LIB


def check(status, what):
    if status != 0:
        raise RuntimeError(f"{what} failed with native status {status}")


def b(text):
    return text.encode()


def cstrings(values):
    array = (ctypes.c_char_p * len(values))(*[b(v) for v in values])
    return array


def create_store(store):
    check(native().skills_workspace_revision_store_create(b(store)), "store_create")


def tree(store, files):
    """files: dict path -> (bytes, executable)."""
    paths = sorted(files)
    n = len(paths)
    cpaths = cstrings(paths)
    buffers = [ctypes.create_string_buffer(files[p][0], len(files[p][0]) or 1)
               for p in paths]
    u8p = ctypes.POINTER(ctypes.c_uint8)
    datas = (u8p * n)(*[ctypes.cast(buf, u8p) for buf in buffers])
    counts = (ctypes.c_ssize_t * n)(*[len(files[p][0]) for p in paths])
    flags = (ctypes.c_int32 * n)(*[1 if files[p][1] else 0 for p in paths])
    out = ctypes.create_string_buffer(OID)
    check(native().skills_workspace_revision_tree_create(
        b(store), cpaths, datas, counts, flags, n, out, OID), "tree_create")
    return out.value.decode()


def commit(store, tree_oid, parents, kind):
    out = ctypes.create_string_buffer(OID)
    if not parents:
        check(native().skills_workspace_revision_commit_create_root(
            b(store), b(tree_oid), out, OID), "commit_create_root")
    else:
        check(native().skills_workspace_revision_commit_create(
            b(store), b(tree_oid), cstrings(parents), len(parents), KIND[kind],
            out, OID), "commit_create")
    return out.value.decode()


def read_files(store, oid):
    lib = native()
    need = ctypes.c_ssize_t(0)
    lib.skills_workspace_revision_tree_list(b(store), b(oid), None, 0, ctypes.byref(need))
    buf = (ctypes.c_uint8 * max(need.value, 1))()
    check(lib.skills_workspace_revision_tree_list(
        b(store), b(oid), buf, need.value, ctypes.byref(need)), "tree_list")
    files = {}
    for line in bytes(buf[: need.value]).decode().splitlines():
        path, mode, blob, size = line.split("\t")
        size = int(size)
        data = (ctypes.c_uint8 * max(size, 1))()
        got = ctypes.c_ssize_t(0)
        check(lib.skills_workspace_revision_blob_read(
            b(store), b(blob), data, max(size, 1), ctypes.byref(got)), "blob_read")
        files[path] = (bytes(data[:size]), mode == "100755")
    return files


def file_digests(store, oid):
    return {p: hashlib.sha256(data).hexdigest()
            for p, (data, _) in sorted(read_files(store, oid).items())}


def skill_files(rng, name, size_kib=6, binary_kib=0):
    """A Skill of typical shape: SKILL.md, references, a small script."""
    words = ("agent skill workspace revision pack upload cloud device "
             "history reconcile merge draft publish review tag note").split()

    def prose(kib):
        out = []
        while sum(len(x) + 1 for x in out) < kib * 1024:
            out.append(" ".join(rng.choice(words) for _ in range(12)) + ".")
        return ("\n".join(out) + "\n").encode()

    files = {
        "SKILL.md": (f"---\nname: {name}\ndescription: Prototype Skill.\n---\n\n"
                     .encode() + prose(max(1, size_kib // 3)), False),
        "references/guide.md": (prose(max(1, size_kib // 3)), False),
        "references/examples.md": (prose(max(1, size_kib // 3)), False),
        "scripts/run.py": (b"#!/usr/bin/env python3\nprint('hello')\n", True),
    }
    if binary_kib:
        files["assets/data.bin"] = (rng.randbytes(binary_kib * 1024), False)
    return files


def edit(rng, files, step, path=None):
    files = dict(files)
    path = path or rng.choice(["SKILL.md", "references/guide.md", "references/examples.md"])
    data, ex = files[path]
    files[path] = (data + f"Edit {step}: {rng.random():.12f}\n".encode(), ex)
    return files


def cmd_fixture(args):
    rng = random.Random(args.seed)
    create_store(args.store)
    files = skill_files(rng, "fixture", args.size_kib, args.binary_kib)
    head = commit(args.store, tree(args.store, files), [], "initial")
    for step in range(1, args.commits):
        files = edit(rng, files, step)
        head = commit(args.store, tree(args.store, files), [head], "local-publish")
    upstream = None
    if args.side:
        side = skill_files(random.Random(args.seed + 1), "upstream", args.size_kib)
        upstream = commit(args.store, tree(args.store, side), [], "initial")
        for step in range(1, args.side):
            side = edit(rng, side, step)
            upstream = commit(args.store, tree(args.store, side), [upstream], "upstream")
    print(json.dumps({"effective": head, "upstream": upstream}))


def cmd_bulk(args):
    """P4 sizing: each commit adds new files of fresh text or random bytes."""
    rng = random.Random(args.seed)
    create_store(args.store)
    files = skill_files(rng, "bulk")
    head = commit(args.store, tree(args.store, files), [], "initial")
    per = max(1, args.files // args.commits)
    made = 0
    step = 0
    while made < args.files:
        step += 1
        for _ in range(min(per, args.files - made)):
            if args.kind == "binary":
                data = rng.randbytes(args.kib * 1024)
            else:
                data = skill_files(rng, "x", size_kib=args.kib * 3)["references/guide.md"][0]
            files[f"data/{made:05d}.{'bin' if args.kind == 'binary' else 'md'}"] = (data, False)
            made += 1
        head = commit(args.store, tree(args.store, files), [head], "local-publish")
    print(json.dumps({"effective": head, "commits": step + 1, "files": made}))


def cmd_edit(args):
    rng = random.Random(args.seed)
    files = edit(rng, read_files(args.store, args.parent), args.seed, args.path)
    oid = commit(args.store, tree(args.store, files), [args.parent], "local-publish")
    print(json.dumps({"commit": oid}))


def cmd_export(args):
    os.makedirs(args.out, exist_ok=False)
    started = time.perf_counter()
    check(native().skills_workspace_revision_export_pack_create(
        b(args.store), b(args.out), cstrings(args.roots), len(args.roots)),
        "export_pack_create")
    elapsed = time.perf_counter() - started
    pack = os.path.abspath(os.path.join(args.out, "objects.pack"))
    data = open(pack, "rb").read()
    print(json.dumps({"pack": pack, "bytes": len(data),
                      "sha256": hashlib.sha256(data).hexdigest(),
                      "ms": round(elapsed * 1000, 1)}))


def stage(store, pack, roots, staging):
    os.makedirs(os.path.join(staging, "pack"), exist_ok=False)
    name = ctypes.create_string_buffer(64)
    status = native().skills_workspace_revision_pack_import(
        b(store), b(staging), b(pack), cstrings(roots), len(roots), name, 64)
    return status, name.value.decode()


def cmd_stage(args):
    """Index into staging beside the live Store; never writes the live Store."""
    status, name = stage(args.store, args.pack, args.roots, args.staging)
    print(json.dumps({"status": status, "packName": name}))
    sys.exit(0 if status == 0 else 3)


def cmd_import(args):
    """Stage, copy the live Store to a candidate, add the pack, verify, swap.

    Mirrors prepareRemoteRevisionStore in the Workspace composition.
    """
    store = os.path.abspath(args.store)
    if not os.path.exists(store):
        create_store(store)
    work = store + ".import"
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    candidate = os.path.join(work, "candidate")
    shutil.copytree(store, candidate, symlinks=True)
    started = time.perf_counter()
    status, name = stage(candidate, args.pack, args.roots, os.path.join(work, "staging"))
    if status != 0:
        shutil.rmtree(work)
        print(json.dumps({"status": status}))
        sys.exit(3)
    if name:
        for ext in ("pack", "idx"):
            shutil.copy2(os.path.join(work, "staging", "pack", f"pack-{name}.{ext}"),
                         os.path.join(candidate, "objects", "pack", f"pack-{name}.{ext}"))
    check(native().skills_workspace_revision_store_open_verify(b(candidate)),
          "store_open_verify")
    old = os.path.join(work, "old")
    os.rename(store, old)
    os.rename(candidate, store)
    shutil.rmtree(work)
    print(json.dumps({"status": 0, "packName": name,
                      "ms": round((time.perf_counter() - started) * 1000, 1)}))


def cmd_merge(args):
    lib = native()
    base = ctypes.create_string_buffer(OID)
    check(lib.skills_workspace_revision_merge_base(
        b(args.store), b(args.local), b(args.remote), base, OID), "merge_base")
    out = ctypes.create_string_buffer(OID)
    need = ctypes.c_ssize_t(0)
    count = ctypes.c_ssize_t(0)
    conflicts = (ctypes.c_uint8 * 4096)()
    check(lib.skills_workspace_revision_merge_sync(
        b(args.store), base.value, b(args.local), b(args.remote), out, OID,
        conflicts, 4096, ctypes.byref(need), ctypes.byref(count)), "merge_sync")
    if count.value:
        print(json.dumps({"conflicts": count.value}))
        sys.exit(4)
    oid = commit(args.store, out.value.decode(), [args.local, args.remote],
                 "sync-candidate")
    print(json.dumps({"commit": oid, "base": base.value.decode()}))


def cmd_graph(args):
    """Every commit reachable from roots, with parents (read-only system Git)."""
    out = subprocess.run(
        ["git", "--git-dir", args.store, "rev-list", "--parents", *args.roots],
        check=True, capture_output=True, text=True,
        env={"GIT_CONFIG_NOSYSTEM": "1", "HOME": "/nonexistent", "PATH": os.environ["PATH"]},
    ).stdout
    graph = {}
    for line in out.splitlines():
        oid, *parents = line.split()
        graph[oid] = parents
    print(json.dumps({"commits": len(graph), "graph": graph}))


def cmd_files(args):
    print(json.dumps({"files": file_digests(args.store, args.commit)}))


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fixture")
    f.add_argument("store")
    f.add_argument("--commits", type=int, default=500)
    f.add_argument("--side", type=int, default=0)
    f.add_argument("--seed", type=int, default=1)
    f.add_argument("--size-kib", type=int, default=6)
    f.add_argument("--binary-kib", type=int, default=0)
    f.set_defaults(fn=cmd_fixture)
    e = sub.add_parser("edit")
    e.add_argument("store")
    e.add_argument("parent")
    e.add_argument("--seed", type=int, default=7)
    e.add_argument("--path")
    e.set_defaults(fn=cmd_edit)
    k = sub.add_parser("bulk")
    k.add_argument("store")
    k.add_argument("--files", type=int, required=True)
    k.add_argument("--kib", type=int, required=True)
    k.add_argument("--kind", choices=["text", "binary"], required=True)
    k.add_argument("--commits", type=int, default=20)
    k.add_argument("--seed", type=int, default=3)
    k.set_defaults(fn=cmd_bulk)
    x = sub.add_parser("export")
    x.add_argument("store")
    x.add_argument("out")
    x.add_argument("roots", nargs="+")
    x.set_defaults(fn=cmd_export)
    s = sub.add_parser("stage")
    s.add_argument("store")
    s.add_argument("pack")
    s.add_argument("staging")
    s.add_argument("roots", nargs="+")
    s.set_defaults(fn=cmd_stage)
    i = sub.add_parser("import")
    i.add_argument("store")
    i.add_argument("pack")
    i.add_argument("roots", nargs="+")
    i.set_defaults(fn=cmd_import)
    m = sub.add_parser("merge")
    m.add_argument("store")
    m.add_argument("local")
    m.add_argument("remote")
    m.set_defaults(fn=cmd_merge)
    g = sub.add_parser("graph")
    g.add_argument("store")
    g.add_argument("roots", nargs="+")
    g.set_defaults(fn=cmd_graph)
    fl = sub.add_parser("files")
    fl.add_argument("store")
    fl.add_argument("commit")
    fl.set_defaults(fn=cmd_files)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
