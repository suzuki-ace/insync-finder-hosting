#!/usr/bin/env python3
# insync-url : ローカル(Insync同期先)のファイル/フォルダ → Google Drive のURL
# 使い方:
#   python3 insync-url.py "/Users/you/Insync/.../file.pdf"
# 動作: Insyncの同期台帳(SQLite)を読み、パス→DriveファイルID→URL を組み立て、
#       URLをクリップボードにコピーし、通知を出す。台帳は読むだけ(tempにコピー)。

import sys, os, glob, shutil, tempfile, sqlite3, subprocess

INSYNC_DATA = os.path.expanduser("~/Library/Application Support/Insync/data")

def notify(title, message):
    try:
        subprocess.run(["/usr/bin/osascript", "-e",
                        'display notification "%s" with title "%s"'
                        % (message.replace('"', "'"), title.replace('"', "'"))],
                       check=False)
    except Exception:
        pass

def clip(text):
    try:
        p = subprocess.Popen(["/usr/bin/pbcopy"], stdin=subprocess.PIPE)
        p.communicate(text.encode("utf-8"))
    except Exception:
        pass

def build_url(cl_id, is_folder):
    if is_folder:
        return "https://drive.google.com/drive/folders/%s" % cl_id
    return "https://drive.google.com/open?id=%s" % cl_id

def walk_path(con, path):
    roots = con.execute(
        "SELECT n.node_id,f.fs_name FROM nodes n JOIN fs_items f ON f.node_id=n.node_id "
        "WHERE n.parent_id IS NULL AND f.fs_name LIKE '/%'").fetchall()
    best = None
    for nid, base in roots:
        if base and (path == base or path.startswith(base.rstrip("/") + "/")):
            if best is None or len(base) > len(best[1]):
                best = (nid, base)
    if not best:
        return None
    nid, base = best
    cur = nid
    for seg in [s for s in path[len(base):].strip("/").split("/") if s]:
        row = con.execute(
            "SELECT n.node_id FROM nodes n JOIN fs_items f ON f.node_id=n.node_id "
            "WHERE n.parent_id=? AND f.fs_name=?", (cur, seg)).fetchone()
        if not row:
            return None
        cur = row[0]
    row = con.execute("SELECT cl_id,cl_type FROM cl_items WHERE node_id=?", (cur,)).fetchone()
    return (row[0], row[1] in ("dir", "folder")) if row else None

def lookup(path):
    path = os.path.realpath(path)
    try:
        ino = str(os.stat(path).st_ino)
    except OSError:
        ino = None
    is_dir = os.path.isdir(path)
    for db in glob.glob(os.path.join(INSYNC_DATA, "gd-*.db")):
        tmpdir = tempfile.mkdtemp(prefix="insyncurl_")
        try:
            tmp = os.path.join(tmpdir, "idx.db")
            shutil.copy(db, tmp)
            for ext in ("-wal", "-shm"):
                if os.path.exists(db + ext):
                    shutil.copy(db + ext, tmp + ext)
            con = sqlite3.connect(tmp)
            if ino:
                r = con.execute(
                    "SELECT c.cl_id,c.cl_type FROM fs_items f JOIN cl_items c ON c.node_id=f.node_id "
                    "WHERE f.fs_ino=?", (ino,)).fetchone()
                if r:
                    con.close()
                    return r[0], (r[1] in ("dir", "folder")) or is_dir, "inode"
            r = walk_path(con, path)
            con.close()
            if r:
                return r[0], r[1] or is_dir, "path"
        except Exception:
            pass
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)
    return None

def main():
    if len(sys.argv) < 2:
        print("使い方: python3 insync-url.py <ファイルパス>", file=sys.stderr)
        sys.exit(1)
    path = sys.argv[1]
    res = lookup(path)
    if not res:
        notify("Drive URL", "見つかりません（Insync同期外/未同期の可能性）")
        print("NOT FOUND:", path, file=sys.stderr)
        sys.exit(2)
    cl_id, is_folder, method = res
    url = build_url(cl_id, is_folder)
    clip(url)
    notify("Drive URL をコピーしました", url)
    # 標準出力にはURLだけ（検証時は "# method=..." も stderr に出す）
    print(url)
    print("# matched by: %s" % method, file=sys.stderr)

if __name__ == "__main__":
    main()
