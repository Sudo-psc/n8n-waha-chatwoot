#!/usr/bin/env bash
set -Eeuo pipefail

# security_scan.sh - Analisa vulnerabilidades em um repositório
# Uso: ./security_scan.sh [caminho] [arquivo_saida]
# - caminho: diretório do repositório (padrão: .)
# - arquivo_saida: JSON gerado (padrão: security-report.json)

repositorio="${1:-.}"
saida="${2:-security-report.json}"

tmpdir=$(mktemp -d)
python_results="$tmpdir/bandit.json"
node_results="$tmpdir/npm_audit.json"
grep_results="$tmpdir/grep.txt"

total=0

scan_python=false
scan_node=false

if [ -f "$repositorio/requirements.txt" ] || find "$repositorio" -name '*.py' | grep -q .; then
  scan_python=true
fi

if [ -f "$repositorio/package.json" ]; then
  scan_node=true
fi

if $scan_python; then
  pip install -q bandit >/dev/null
  bandit -r "$repositorio" -f json -o "$python_results" || true
  total=$((total + $(jq '.results | length' "$python_results")))
fi

if $scan_node; then
  (cd "$repositorio" && npm install --ignore-scripts >/dev/null 2>&1)
  (cd "$repositorio" && npm audit --json > "$node_results") || true
  node_vuln=$(jq '.metadata.vulnerabilities.critical + .metadata.vulnerabilities.high + .metadata.vulnerabilities.moderate + .metadata.vulnerabilities.low' "$node_results")
  total=$((total + node_vuln))
fi

grep -nEi 'password|secret|token' -r "$repositorio" > "$grep_results" || true
grep_vuln=$(wc -l < "$grep_results")
total=$((total + grep_vuln))

cat <<JSON > "$saida"
{
  "total_vulnerabilities": $total,
  "grep_matches": $grep_vuln,
  "bandit_results": $( [ -f "$python_results" ] && cat "$python_results" || echo "null" ),
  "npm_audit": $( [ -f "$node_results" ] && cat "$node_results" || echo "null" )
}
JSON

echo "Relatório salvo em $saida"
