#!/usr/bin/env bash
set -Eeuo pipefail
# Torna todos os scripts .sh executáveis

find . -name '*.sh' -not -path './.git/*' -print0 | while IFS= read -r -d '' file; do
  chmod +x "$file"
  echo "Arquivo $file agora é executável"
done
