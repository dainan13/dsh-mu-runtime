#!/usr/bin/env python3
"""给 channels/runtimes.json 里缺 size 的条目补上资产大小（字节）。

在**能访问 GitHub 的机器**上运行 ✓（HEAD 请求只取 Content-Length ✓ 不下载）
  python3 tools/fill-sizes.py            # 补空缺
  python3 tools/fill-sizes.py --force    # 全部重取
"""
import json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IDX = os.path.join(ROOT, "channels", "runtimes.json")
UA = "Mozilla/5.0 (X11; Linux x86_64) Chrome/126 Safari/537.36"


def head_size(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        n = r.headers.get("Content-Length")
        return int(n) if n else 0


def main():
    force = "--force" in sys.argv
    doc = json.load(open(IDX, encoding="utf-8"))
    changed = 0
    for row in doc.get("runtimes", []):
        if row.get("size") and not force:
            continue
        try:
            size = head_size(row["url"])
        except Exception as exc:
            print(f"  skip {row.get('id')}: {exc}")
            continue
        if size:
            row["size"] = size
            changed += 1
            print(f"  {row['id']}: {size / 1048576:.1f} MB")
    if changed:
        json.dump(doc, open(IDX, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
        open(IDX, "a", encoding="utf-8").write("\n")
    print(f"updated {changed} entr{'y' if changed == 1 else 'ies'}")


if __name__ == "__main__":
    main()
