#!/usr/bin/env python3
"""把 channels/channels.json 与 channels/runtimes.json 里的**旧 id** 规范成
   <dsh>-<variant>[-r<rev>]-<sha256[:6]>  ✓

为什么必须统一：平台安装时的 id 就是按这个格式生成的 ✓
如果清单里写的是旧 id（0.2.2-rc.1 这种），装完会变成带指纹的另一个名字 ✗
用户会以为"装错了" ✗

用法：
  python3 tools/normalize-index.py            # 改写两个文件
  python3 tools/normalize-index.py --dry-run  # 只打印
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CH = os.path.join(ROOT, "channels", "channels.json")
IDX = os.path.join(ROOT, "channels", "runtimes.json")
FP = re.compile(r"-[0-9a-f]{6,12}$")


def split_id(rid, dsh="", variant="", rev=0):
    """旧 id → (dsh, variant, rev, fp)"""
    fp = ""
    m = FP.search(rid or "")
    if m and re.search(r"[0-9]", m.group(0)):
        fp = m.group(0)[1:]
        rid = rid[:m.start()]
    dsh = dsh or rid
    return dsh, (variant or "plain"), int(rev or 0), fp


def canon(row):
    rid = str(row.get("id") or "")
    dsh, variant, rev, _fp = split_id(rid, row.get("dsh") or "", row.get("variant") or "",
                                      row.get("rev") or 0)
    sha = str(row.get("sha256") or "").lower()
    fp = sha[:6] if sha else _fp
    if not fp:
        return row, False                       # 没有 sha 也没指纹 → 保持原样（打印提醒）
    new = f"{dsh}-{variant}" + (f"-r{rev}" if rev else "") + f"-{fp}"
    if row.get("id") == new:
        return row, False
    row = dict(row)
    row["id"] = new
    return row, True


def main():
    dry = "--dry-run" in sys.argv
    changed = 0
    for path in (CH, IDX):
        try:
            doc = json.load(open(path, encoding="utf-8"))
        except Exception as exc:
            print(f"skip {path}: {exc}")
            continue
        rows = doc.get("runtimes") if isinstance(doc.get("runtimes"), list) else None
        if rows is None:
            rows = []
            for key in ("default", "alpha", "beta", "stable"):
                if isinstance(doc.get(key), dict) and doc[key]:
                    rows.append(doc[key])
                elif isinstance(doc.get(key), list):
                    rows.extend(doc[key])
            wrap = False
        else:
            wrap = True
        out = []
        for row in rows:
            new, did = canon(row)
            if did:
                changed += 1
                print(("would rename" if dry else "rename") + f": {row.get('id')} -> {new.get('id')}")
            out.append(new)
        if dry:
            continue
        if wrap:
            doc["runtimes"] = out
        else:
            i = 0
            for key in ("default", "alpha", "beta", "stable"):
                if isinstance(doc.get(key), dict) and doc[key]:
                    doc[key] = out[i]; i += 1
                elif isinstance(doc.get(key), list):
                    doc[key] = out[i:i + len(doc[key])]; i += len(doc[key])
            doc["schema"] = 2
        json.dump(doc, open(path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
        open(path, "a", encoding="utf-8").write("\n")
    print(("would change" if dry else "changed") + f" {changed} entr{'y' if changed == 1 else 'ies'}")


if __name__ == "__main__":
    main()
