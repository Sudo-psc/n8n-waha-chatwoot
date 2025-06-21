# Instruções para contribuidores

Estas diretrizes se aplicam a todo o repositório.

## Estilo de scripts Shell
- Utilize `#!/usr/bin/env bash` na primeira linha.
- Habilite `set -Eeuo pipefail` logo após o shebang.
- Indente com dois espaços.
- Prefira comentários em português.

## Testes obrigatórios
- Ao alterar qualquer arquivo `.sh`, execute `shellcheck <arquivo>` e corrija eventuais avisos.
