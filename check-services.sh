#!/usr/bin/env bash
# Verifica portas abertas e testa URLs dos três serviços
set -euo pipefail

declare -A urls=(
  [Chatwoot]="https://chat.saraivavision.com.br"
  [WAHA]="https://waha.saraivavision.com.br"
  [n8n]="https://n8n.saraivavision.com.br"
)

echo "=== Portas em escuta (22,80,443,3000-3002) ==="
ss -ltnp '( sport = :22 or sport = :80 or sport = :443 or sport = :3000 or sport = :3001 or sport = :3002 )' || true
echo

for name in "${!urls[@]}"; do
  url=${urls[$name]}
  code=$(curl -ks -o /dev/null -w '%{http_code}' "$url" || true)
  printf "%-8s => %-45s HTTP %s\n" "$name" "$url" "$code"
done
