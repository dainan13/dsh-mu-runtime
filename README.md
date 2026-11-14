# dsh-mu-runtime

DSH 运行时的**纯净预装包**：一个 squashfs 镜像，里面是 node + npm + `@deepseek-ai/dsh@X`
+ 依赖 + 已编译好的 musl `node-pty`。**不含任何 dsh-mu 代码**，可 sha256 校验。

## 为什么需要它

平台最初的做法是在客户机上"现场 `npm install` + `node-gyp` 编 node-pty"：

- 30–50 分钟，内存峰值很高（实测把一台机器压到 load 45）；
- 中途 npm 会先删旧包，**运行时装到一半的窗口里，任何实例重启都起不来**；
- musl 没有 node-pty 预编译包，编译失败就静默缺 `pty.node`，用户点「终端」才发现。

打包成镜像后：安装 = 挂载（秒级）、不需要网络、字节级确定、回滚 = 换一个 id。

## 产物与命名

每次发布产出三个资产（release 名 `runtime-<id>`）：

```
dsh-<id>.squashfs        运行时镜像（zstd squashfs，~95–100 MB）
dsh-<id>.manifest.json   构建元数据（dsh 版本、node-pty 版本、arch/libc、pty sha256）
SHA256SUMS               校验和（平台下载后用它对镜像校验）
```

`<id>` = `<dsh>-<variant>[-r<rev>]-<sha6>`

* `variant`：CI 默认 `plain`；本地 `build.sh` 默认 `local`；也可以是 `vscode` 之类的变体
* `sha6`：镜像 sha256 的前 6 位（内容指纹）
* ⇒ 同一个 DSH 版本可以有任意多个构建，互不覆盖；**清单里的 id 就是装完的 id**

## 两个清单（`channels/`）

| 文件 | 作用 | 维护者 |
| --- | --- | --- |
| `channels.json` | **指针**：`default` / `alpha` 各一条 | CI（`channel` 参数）|
| `runtimes.json` | **历史**：每次发布追加一条（id/dsh/variant/rev/sha256/size/url/built_at），最多 100 条 | CI |

平台侧的「读取线上版本」**只读 `runtimes.json`**（浏览器直连），列出全部历史并标出默认；
`dsh-muctl runtime install`（不带版本）读 `channels.json` 的 `default`。

## 构建

```sh
# 本地（需要 docker；默认 variant=local）
sh build.sh 0.2.2-rc.1 0        # 产物在 dist/
sh build.sh 0.2.2-rc.1 1 vscode # 变体 + rev 1

# CI：Actions → runtime-release → Run workflow
#   dsh_version / rev / variant / channel(none|default|alpha) / arch
#   会构建 → 发 release → 更新 channels/runtimes.json（channel≠none 时再更新 channels.json）
```

CI 里 `variant` 留空视为 `plain`；`rev=0` 时 id 不带 `-r0`。

## 工具

```sh
python3 tools/normalize-index.py [--dry-run]   # 把旧 id 规范成 <dsh>-<variant>-<sha6>
python3 tools/fill-sizes.py                    # 给缺 size 的条目补资产大小（只发 HEAD）
```

## 内网镜像（客户机不出网时）

把 `channels/*.json` 与 `.squashfs` 放到客户可达的位置（NAS / 文件服务器 / 对象存储），
客户机的 `runtime_channel_base` 指向那份 `channels.json` 即可。平台会把
`channels.json` 同目录的 `runtimes.json` 一起读，历史列表照常可用，**完全不碰 GitHub**。

也可以用 admin 的「上传镜像」：页面会显示进度、预计剩余时间，可取消，失败会显示原因。

## 与平台的关系

```
运行时镜像（本仓库）      ← 平台安装/切换/校验，admin「运行 → 运行时」或 dsh-muctl runtime
平台 dsh-mu（另一个仓库）  ← admin / 网关 / jail / CLI，依赖运行时镜像是"一个含 node_modules 的目录"
```

运行时只提供 `node_modules`；平台把它只读挂进每个实例的 jail（`/usr/local/lib/node_modules`）。
