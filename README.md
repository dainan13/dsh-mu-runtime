# dsh-mu-runtime

DSH 运行时的**纯净预装包**。一个 apk = node + npm + `@deepseek-ai/dsh@X` + 依赖 + 已编译的
`node-pty`。**不含任何 dsh-mu 代码**，可以 hash 校验。

## 为什么要它

现状是平台在客户机上"现场 npm install + node-gyp 编 node-pty"：

- 30–50 分钟，内存峰值很高（node-gyp 编译），实测把一台机器压到 load 45；
- 中途 npm 会先删掉旧包，**运行时装到一半的窗口里，任何实例重启都起不来**；
- musl 没有 node-pty 预编译包，编译失败就静默缺 `pty.node`，用户点「终端」才发现。

打包成 apk 之后：安装 = 解包（秒级）、不需要网络、字节级确定、回滚 = 装旧 apk。

## 分层与边界

```
L0  dsh-mu-runtime-<dshver>-r0.apk     ← 本仓库。纯净运行时，零我方代码。
L1  dsh-mu-<ver>-r0.apk                ← 平台（admin / 网关 / jail / CLI / 注入）
```

我们对 DSH 的"侵入"全部发生在 **L1**，且都不碰 DSH 的文件：

| 侵入点 | 落点 | 是否改 DSH 包 |
| --- | --- | --- |
| `mu-shell.js`（侧栏卡 / F2） | 网关 `sub_filter` 注入 | 否 |
| `dsh-client-models` 插件 | 实例 profile（官方插件机制） | 否 |
| `cordis.patch.yml` | 实例 profile（官方 overlay） | 否 |
| `pty.node` | 运行时依赖的二进制 | 本包负责 |

真正耦合的是**接口契约**（DOM 结构、插件 slot API、patch schema），由平台侧的
`compat.json`（支持的 DSH 版本区间）+ `dsh-muctl runtime verify`（版本 / 原生模块 /
selector-drift）管住，而不是靠改 DSH 源码。

## 版本与命名

```
pkgver   = DSH 版本，`-` 换成 `_`（apk 版本规则）：0.2.2-rc.1 → 0.2.2_rc.1
pkgrel   = r0
包名     = dsh-mu-runtime
文件     = dsh-mu-runtime-0.2.2_rc.1-r0.apk
校验     = 同目录 SHA256SUMS；包内 /usr/local/lib/dsh-mu-runtime/MANIFEST.json
          记录 { dsh, node, node_pty, built_at, arch, sha256_of_pty } 
```

## 包内布局

```
/usr/local/lib/dsh-mu-runtime/
  node/bin/node                 node 24.x（DSH engines 要求 >= 24.9）
  npm/                          该 node 自带 npm
  dsh/                          @deepseek-ai/dsh@<ver> + node_modules（含已编译 pty.node）
  MANIFEST.json                 见上
  LICENSE.dsh                   上游 MIT 许可正文（再分发要求）
/etc/dsh-mu-runtime/version     纯文本版本，平台快速比对
```

平台侧把它挂/链进 gateway rootfs 的 `/usr/local/lib/node_modules/@deepseek-ai/dsh`
（沿用现在的 `DSH_RUNTIME_DIR` 约定，实例不用改）。

## 构建

```sh
# 本机（需要 docker）
./build.sh 0.2.2-rc.1            # 产出 dist/dsh-mu-runtime-0.2.2_rc.1-r0.apk + SHA256SUMS

# CI：.github/workflows/runtime-release.yml
#   手动触发（workflow_dispatch），输入版本；产物挂到本仓库 release
```

构建在 `node:24-alpine` 里做，目的是让 `pty.node` 链接到 **musl**，与目标机一致。
构建完立刻在干净的 `alpine:3.24` 里做一次"像用户那样装一遍"的验证（`verify.sh`）。

## 安装（平台会自动做）

```sh
apk add --allow-untrusted ./dsh-mu-runtime-0.2.2_rc.1-r0.apk
dsh-muctl runtime use 0.2.2-rc.1     # 指向它并校验（平台命令，后续实现）
```

## 回滚

```sh
apk add --allow-untrusted ./dsh-mu-runtime-0.2.1_rc.5-r0.apk
dsh-muctl runtime use 0.2.1-rc.5
```
