set -eu
# O documento SSM serializa os comandos e só aceita os modos declarados.
exec 9>/run/prominence-control.lock
flock -n 9 || exit 0
state=/run/prominence-idle
unit=minecraft.service
if ! systemctl is-active --quiet "$unit"; then
    rm -f "$state"
    echo "Serviço inativo. EC2 preservada."
    exit 0
fi
if [ "$mode" = idle ]; then
    rc=0
    python3 - "$state" "$minutes" <<'PY' || rc=$?
import json
import pathlib
import socket
import struct
import subprocess
import sys
import time

state = pathlib.Path(sys.argv[1])
threshold = int(sys.argv[2]) * 60


def varint(n):
    result = bytearray()
    while n >= 128:
        result.append((n & 127) | 128)
        n >>= 7
    return result + bytes([n])


def read_int(stream):
    result = 0
    for shift in range(0, 35, 7):
        data = stream.read(1)
        if not data:
            raise EOFError("Resposta Minecraft incompleta")
        result |= (data[0] & 127) << shift
        if data[0] < 128:
            return result
    raise ValueError("VarInt inválido")


def online():
    host = b'localhost'
    handshake = b'\x00' + varint(763) + varint(len(host)) + host + struct.pack('>H', 25565) + b'\x01'
    with socket.create_connection(('127.0.0.1', 25565), timeout=4) as conn:
        conn.sendall(varint(len(handshake)) + handshake + b'\x01\x00')
        with conn.makefile('rb') as stream:
            size = read_int(stream)
            if not 0 < size <= 2**20 or read_int(stream) != 0:
                raise ValueError("Resposta de status inesperada")
            length = read_int(stream)
            if not 0 < length <= size:
                raise ValueError("Tamanho inválido")
            count = json.loads(stream.read(length))['players']['online']
            if type(count) is not int or count < 0:
                raise ValueError("Contagem inválida")
            return count


try:
    now = int(time.monotonic())
    invocation = subprocess.check_output(['systemctl', 'show', 'minecraft.service',
        '--property=InvocationID', '--value'], text=True).strip()
    if not invocation:
        raise ValueError("Sem identificação do processo")
    start = now
    if state.exists():
        previous = json.loads(state.read_text())
        if previous['unit'] == invocation and 0 <= now - previous['seen'] <= 420:
            start = previous['start']
    # Uma sessão curta entre sondagens também reinicia a contagem.
    logs = subprocess.check_output(['journalctl', '-u', 'minecraft.service',
        '-b', '--since', '8 minutes ago', '--no-pager', '-o', 'json'], text=True)
    for line in logs.splitlines():
        record = json.loads(line)
        message = record.get('MESSAGE', '')
        if isinstance(message, str) and any(marker in message for marker in
                (' joined the game', ' left the game', ' logged in with entity id')):
            start = max(start, int(record['__MONOTONIC_TIMESTAMP']) // 1_000_000)
    players = online()
    if players:
        start = now
    ready = now - start >= threshold
    if ready and online() > 0:
        start = now
        ready = False
    state.write_text(json.dumps({'unit': invocation, 'start': start, 'seen': now}))
    print(f'Jogadores: {players}. Janela observada: {now-start}s.')
except Exception:
    state.unlink(missing_ok=True)
    raise
sys.exit(0 if ready else 10)
PY
    [ "$rc" != 10 ] || exit 0
    [ "$rc" = 0 ] || exit "$rc"
fi
systemctl stop "$unit"
result=$(systemctl show "$unit" -p Result --value)
if [ "$result" != success ]; then
    status=$(systemctl show "$unit" -p ExecMainStatus --value)
    # A JVM pode traduzir o SIGTERM solicitado pelo systemd no código 143.
    [ "$result:$status" = exit-code:143 ] || { echo "Falha: $result/$status" >&2; exit 1; }
fi
sync
systemctl poweroff --no-block
