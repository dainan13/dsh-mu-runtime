#!/bin/sh
# 构建 dsh-mu-runtime apk。
#   容器模式（CI 默认）： ./build.sh 0.2.2-rc.1
#   就地模式（在已 chroot 的 rootfs 里跑）： ./build.sh --here 0.2.2-rc.1
#
# 设计要点（都在 .61 上实测过）：
#   · 只装 linux-musl-x64：--cpu=x64 --os=linux --libc=musl --omit=optional --ignore-scripts
#   · prune 掉 *.map / *.d.ts / *.md / tests / test / docs / examples（实测 715MB → 464MB）
#   · **不编译** node-pty：复用一份已编译好的 musl pty.node（$PTY_SRC，实测 75984 字节）
#   · **不打包 node/npm**：apk 依赖 nodejs>=24.9（省 50MB 安装、17.7MB 下载）
#   · 压缩后约 66MB（实测）
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
MODE=container
if [ "${1:-}" = "--here" ]; then MODE=here; shift; fi
VER="${1:?usage: ./build.sh [--here] <dsh-version> [rev]}"
REV="${2:-0}"
VARIANT="${VARIANT:-}"          # 可选：vscode 之类；空 = plain
# apk 的版本语法只接受 `_rc<数字>` 这类后缀（`_rc.1` 里有小数点会报 invalid ✗）
#   0.2.2-rc.1 → 0.2.2_rc1 ; 0.2.2-beta.3 → 0.2.2_beta3 ; 0.2.1 → 0.2.1
PKGVER="$(printf '%s' "$VER" | sed -e 's/\([0-9]\)-rc\.\([0-9]\)/\1_rc\2/' -e 's/\([0-9]\)-beta\.\([0-9]\)/\1_beta\2/' -e 's/-/_/g')"
ARCH="${ARCH:-x86_64}"
NODE_IMAGE="${NODE_IMAGE:-node:24-alpine}"
TARGET_IMAGE="${TARGET_IMAGE:-alpine:3.24}"

recipe() {   # 在目标环境里执行：$1=dsh version, $2=工作目录
	VER="$1"; WORK="$2"
	set -eu
	mkdir -p "$WORK"; cd "$WORK"
	npm init -y >/dev/null 2>&1
	echo "== npm install @deepseek-ai/dsh@$VER (linux-musl-x64, no optional, no scripts) =="
	# --include=optional（默认）是必须的：node-addon-require-builtin 的原生库在
	# **平台可选依赖**里（...-linux-x64-musl）；--cpu/--os/--libc 让 npm 只装匹配那一个 ✓
	npm install --no-audit --no-fund --omit=dev \
		--cpu=x64 --os=linux --libc=musl --ignore-scripts \
		"@deepseek-ai/dsh@$VER" 2>&1 | tail -2
	echo "   installed: $(du -sm node_modules | cut -f1) MB"

	echo "== prune docs/types/tests =="
	find node_modules -name "*.map" -delete
	find node_modules -name "*.d.ts" -delete
	find node_modules -name "*.md" -delete
	# 注意：**不要**删 `doc` —— yaml 的 dist/doc/ 是真正的代码（删了 require 就崩 ✗）
	# 也不要碰 dist/ lib/ 里的目录（那是运行时本体 ✓）
	find node_modules -type d \( -name tests -o -name test -o -name __tests__ \
		-o -name docs -o -name examples -o -name example \) \
		-not -path "*/dist/*" -not -path "*/lib/*" -prune -exec rm -rf {} +
	echo "   pruned:   $(du -sm node_modules | cut -f1) MB"

	echo "== node-pty: reuse a prebuilt musl binary (no compile) =="
	PTY_SRC="${PTY_SRC:-/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/node-pty/build/Release/pty.node}"
	# CI 里没有现成运行时 ⇒ 用仓库里 vendor/node-pty/pty.node（同版本 ✓ 已校验）
	if [ ! -f "$PTY_SRC" ] && [ -f /src/vendor/node-pty/pty.node ]; then
		PTY_SRC=/src/vendor/node-pty/pty.node
	fi
	[ -f "$PTY_SRC" ] || { echo "   !! no prebuilt pty.node at $PTY_SRC"; exit 1; }
	mkdir -p node_modules/node-pty/build/Release
	cp "$PTY_SRC" node_modules/node-pty/build/Release/pty.node
	echo "   copied $(wc -c < node_modules/node-pty/build/Release/pty.node) bytes"

	echo "== smoke test =="
	node -e "require('$WORK/node_modules/node-pty')" && echo "   node-pty loads OK"
	node node_modules/@deepseek-ai/dsh/lib/bin.js --version 2>&1 | tail -1

	echo "== manifest =="
	DSHV="$(node -p "require('./node_modules/@deepseek-ai/dsh/package.json').version")"
	PTYV="$(node -p "require('./node_modules/node-pty/package.json').version")"
	ID="$VER${VARIANT:+-$VARIANT}"
	if [ "${REV:-0}" != "0" ]; then ID="$ID-r$REV"; fi
	cat > MANIFEST.json <<EOF
{
  "schema": 1,
  "id": "$ID",
  "variant": "${VARIANT:-plain}",
  "rev": ${REV:-0},
  "source": "ci",
  "provides": [],
  "dsh": "$DSHV",
  "node_pty": "$PTYV",
  "node_build": "$(node -v)",
  "arch": "$(uname -m)",
  "libc": "musl",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pty_sha256": "$(sha256sum node_modules/node-pty/build/Release/pty.node | cut -d' ' -f1)"
}
EOF
	cat MANIFEST.json
}

if [ "$MODE" = container ]; then
	# 容器里只做一件事：调用本脚本的 --here 分支（它自己会产出 squashfs + manifest）
	# 早先这里多写了一段 cp（以为工作目录里还有 node_modules ✗）→ CI 上必然失败 ✓
	mkdir -p "$HERE/dist"
	docker run --rm \
		-v "$HERE:/src" -v "$HERE/dist:/out" \
		-e VER="$VER" -e REV="$REV" -e VARIANT="${VARIANT:-}" -e ARCH="$ARCH" \
		"$NODE_IMAGE" sh -eu -c '
			apk add --no-cache python3 squashfs-tools bash >/dev/null
			mkdir -p /out
			WORK=/tmp/build-work OUT=/out sh /src/build.sh --here "$VER" "$REV"
		'
	( cd "$HERE/dist" && ls -l && sha256sum dsh-*.squashfs > SHA256SUMS && cat SHA256SUMS )
	echo "== done: $HERE/dist =="
else
	echo "--here: building in the current environment"
	R="${R:-/var/lib/dsh-mu/gateway/rootfs}"
	WORK="${WORK:-/tmp/rtb}"
	rm -rf "$WORK"; mkdir -p "$WORK"
	recipe "$VER" "$WORK"
	OUT="${OUT:-$R/tmp/rt-dist}"; mkdir -p "$OUT/root/usr/local/lib/dsh-mu-runtime" "$OUT/root/etc/dsh-mu-runtime"
	cp -a "$WORK/node_modules" "$WORK/package.json" "$WORK/MANIFEST.json" "$OUT/root/usr/local/lib/dsh-mu-runtime/"
	cp "$WORK"/node_modules/@deepseek-ai/dsh/LICENSE* "$OUT/root/usr/local/lib/dsh-mu-runtime/" 2>/dev/null || true
	printf '%s\n' "$VER" > "$OUT/root/etc/dsh-mu-runtime/version"
	mkdir -p "$OUT/dist"
	# 同上：只打"含 node_modules 的那层"
	mksquashfs "$OUT/root/usr/local/lib/dsh-mu-runtime" "$OUT/dist/dsh-$VER.squashfs" \
		-comp zstd -noappend -quiet >/dev/null
	cp "$WORK/MANIFEST.json" "$OUT/dist/dsh-$VER.manifest.json"
	( cd "$OUT/dist" && sha256sum dsh-*.squashfs > SHA256SUMS && cat SHA256SUMS )
	echo "== done: $OUT/dist =="
fi
