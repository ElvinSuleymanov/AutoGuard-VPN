#!/bin/sh

PEERS_DIR="/config/peers"
INTERFACE="wg0"

until wg show "${INTERFACE}" >/dev/null 2>&1; do
    sleep 1
done

mkdir -p /config/keys
wg show "${INTERFACE}" public-key > /config/keys/server_public.key

mkdir -p "${PEERS_DIR}"

for f in "${PEERS_DIR}"/*.conf; do
    [ -f "$f" ] || continue
    wg addconf "${INTERFACE}" "$f" \
        && echo "[peer-watcher] loaded: $(basename "$f")" \
        || echo "[peer-watcher] failed: $(basename "$f")"
done

inotifywait -m -e close_write --format '%f' "${PEERS_DIR}" | \
while IFS= read -r filename; do
    case "${filename}" in
        *.conf)
            wg addconf "${INTERFACE}" "${PEERS_DIR}/${filename}" \
                && echo "[peer-watcher] added: ${filename}" \
                || echo "[peer-watcher] error: ${filename}"
            ;;
    esac
done
