#!/bin/sh

until wg show wg0 public-key >/dev/null 2>&1; do
    sleep 1
done

mkdir -p /config/keys
wg show wg0 public-key > /config/keys/server_public.key
