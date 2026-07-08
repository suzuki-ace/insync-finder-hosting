#!/usr/bin/env python3
# Insync Finder - native messaging host
# Chrome拡張から {"url": "...", "mode": "open"|"reveal"} を受け取り、
# Insyncの同期台帳を引いてローカルの該当ファイルを
#   mode="open"   → macの既定アプリで開く（open <path>）
#   mode="reveal" → Finderで選択表示（open -R <path>）
# DBは読むだけ（tempにコピーして参照）。mode省略時は "open"。

import sys, os, re, json, glob, struct, shutil, tempfile, sqlite3, subprocess

INSYNC_DATA = os.path.expanduser("~/Library/Application Support/Insync/data")

QUERY = """
WITH RECURSIVE anc(node_id,parent_id,path) AS (
  SELECT n.node_id,n.parent_id,COALESCE(f.fs_name,'')
  FROM nodes n LEFT JOIN fs_items f ON f.node_id=n.node_id
  WHERE n.node_id=(SELECT node_id FROM cl_items WHERE cl_id=?)
  UNION ALL
  SELECT n.node_id,n.parent_id,COALESCE(f.fs_name,'')||'/'||anc.path
  FROM nodes n LEFT JOIN fs_items f ON f.node_id=n.node_id
  JOIN anc ON n.node_id=anc.parent_id
)
SELECT path FROM anc WHERE parent_id IS NULL LIMIT 1;
"""

def read_message():
    raw = sys.stdin.buffer.read(4)
    if len(raw) < 4:
        sys.exit(0)
    length = struct.unpack("<I", raw)[0]
    return json.loads(sys.stdin.buffer.read(length).decode("utf-8"))

def send_message(obj):
    data = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(data)))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()

def extract_id(url):
    for pat in (r"/d/([-\w]+)", r"/folders/([-\w]+)", r"[?&]id=([-\w]+)"):
        m = re.search(pat, url)
        if m:
            return m.group(1)
    m = re.search(r"[-\w]{20,}", url)
    return m.group(0) if m else None

def resolve(file_id):
    for db in glob.glob(os.path.join(INSYNC_DATA, "gd-*.db")):
        tmpdir = tempfile.mkdtemp(prefix="insyncfind_")
        try:
            tmp = os.path.join(tmpdir, "idx.db")
            shutil.copy(db, tmp)
            for ext in ("-wal", "-shm"):
                if os.path.exists(db + ext):
                    shutil.copy(db + ext, tmp + ext)
            con = sqlite3.connect(tmp)
            row = con.execute(QUERY, (file_id,)).fetchone()
            con.close()
            if row and row[0]:
                return row[0]
        except Exception:
            pass
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)
    return None

def main():
    try:
        msg = read_message()
    except Exception as e:
        send_message({"ok": False, "error": "メッセージ読み取り失敗: %s" % e})
        return

    url = (msg or {}).get("url", "") or ""
    mode = (msg or {}).get("mode", "open") or "open"   # "open"(既定アプリ) / "reveal"(Finder表示)
    file_id = extract_id(url)
    if not file_id:
        send_message({"ok": False, "error": "URLからIDを取り出せません", "url": url})
        return

    path = resolve(file_id)
    if not path:
        send_message({"ok": False, "error": "同期インデックスに見つかりません（別アカウント/未同期）", "id": file_id})
        return

    if os.path.exists(path):
        if mode == "reveal":
            subprocess.run(["/usr/bin/open", "-R", path])   # Finderで選択表示
        else:
            subprocess.run(["/usr/bin/open", path])         # 既定アプリで開く
        send_message({"ok": True, "path": path, "mode": mode})
    else:
        parent = os.path.dirname(path)
        if os.path.isdir(parent):
            subprocess.run(["/usr/bin/open", parent])
        send_message({"ok": False, "error": "ローカルに実体なし（未DL/部分同期）", "path": path})

if __name__ == "__main__":
    main()
