#!/usr/bin/env bash
# Co-op smoke test: a headless host and a headless client on localhost. The
# client digs a block near spawn; the host must see the hole and the client's
# avatar; the client must see the host's. Usage: tools/nettest.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
tools/ensure_import.sh
PORT=${PORT:-24580}
mkdir -p build
tools/godot.sh --headless --path . -- --smoke --fps=60 --planet=04 --frames=1500 --host=$PORT --name=Host --nettest > build/nettest_host.log 2>&1 &
HOST_PID=$!
sleep 6
tools/godot.sh --headless --path . -- --smoke --fps=60 --join=127.0.0.1:$PORT --frames=600 --name=Client --nettest > build/nettest_client.log 2>&1 &
CLIENT_PID=$!
wait $CLIENT_PID || true
wait $HOST_PID || true
echo "== host =="; grep -E "nettest|net\]|SCRIPT ERROR|ERROR" build/nettest_host.log | head -20
echo "== client =="; grep -E "nettest|net\]|SCRIPT ERROR|ERROR" build/nettest_client.log | head -20
status=0
grep -qE "\[nettest\] host: block [^|]* = 0 " build/nettest_host.log || { echo "!! host did not see the client's dig"; status=1; }
grep -qE "\[nettest\] host: .*remote players 1 " build/nettest_host.log || { echo "!! host did not see the client avatar"; status=1; }
grep -qE "\[nettest\] client: .*remote players 1 " build/nettest_client.log || { echo "!! client did not see the host avatar"; status=1; }
grep -qE "\[nettest\] client: block [^|]* = 0 " build/nettest_client.log || { echo "!! client did not get its own dig applied"; status=1; }
if grep -qE "SCRIPT ERROR" build/nettest_host.log build/nettest_client.log; then echo "!! script errors"; status=1; fi
[[ $status -eq 0 ]] && echo "nettest OK"
exit $status
