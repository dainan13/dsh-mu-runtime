#!/bin/sh
# 在**已安装**的机器上校验运行时是否自洽（平台侧 `dsh-muctl runtime verify` 会做同一件事）。
# 用法： ./verify.sh [<expected-version>]
set -eu
RT="${RT:-/usr/local/lib/dsh-mu-runtime}"
fail() { echo "FAIL  $*" >&2; exit 1; }

[ -f "$RT/MANIFEST.json" ] || fail "MANIFEST.json missing ($RT)"
command -v python3 >/dev/null 2>&1 || fail "python3 needed to parse manifest"

want="${1:-}"
have="$(sed -n 's/.*"dsh": *"\([^"]*\)".*/\1/p' "$RT/MANIFEST.json" | head -1)"
[ -n "$have" ] || fail "cannot read dsh version from manifest"
if [ -n "$want" ] && [ "$want" != "$have" ]; then fail "version mismatch: want $want, have $have"; fi
echo "PASS  manifest dsh=$have"

PTY="$RT/dsh/node_modules/node-pty/build/Release/pty.node"
[ -f "$PTY" ] || fail "pty.node missing — terminals will fail"
echo "PASS  pty.node present ($(wc -c < "$PTY") bytes)"

NODE="$RT/node/bin/node"
if [ -x "$NODE" ]; then
	v="$("$NODE" -v)"
	case "$v" in v2[4-9].*|v[3-9][0-9].*) echo "PASS  node $v (engines >= 24.9)" ;; *) fail "node $v is too old" ;; esac
	"$NODE" -e "process.chdir('$RT/dsh'); require('node-pty'); console.log('PASS  node-pty loads')" \
		|| fail "node-pty failed to load"
else
	echo "WARN  $NODE not found (runtime may rely on the host node)"
fi

[ -f "$RT/LICENSE.dsh" ] || echo "WARN  upstream LICENSE not bundled (MIT requires it on redistribution)"
echo "OK"
