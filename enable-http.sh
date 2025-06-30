#!/usr/bin/env bash
# Remove redirecionamentos HTTPS para habilitar acesso via HTTP

set -Eeuo pipefail
trap 'echo "[ERRO] Linha $LINENO: comando \"$BASH_COMMAND\" falhou" >&2' ERR

[[ $EUID -eq 0 ]] || { echo "[ERRO] Rode como root"; exit 1; }

domains=(
  "chat.example.com"
  "waha.example.com"
  "n8n.example.com"
)

for d in "${domains[@]}"; do
  conf="/etc/nginx/sites-available/${d}"
  if [[ -f $conf ]]; then
    if grep -q "return 301" "$conf"; then
      sed -i '/return 301/d' "$conf"
      echo "[INFO] Redirecionamento removido em $conf"
    else
      echo "[INFO] Nenhum redirecionamento encontrado em $conf"
    fi
  else
    echo "[WARN] Arquivo $conf inexistente" >&2
  fi
done

nginx -t && systemctl reload nginx

echo "Acesso HTTP liberado."
