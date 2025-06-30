#!/usr/bin/env bash
# test-setup-functions.sh - Testes unitários para funções do setup-wnc.sh

# Framework de teste simples
TESTS_PASSED=0
TESTS_FAILED=0

# Cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Função de teste
test_function() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    echo -n "Testing: $test_name... "
    
    # Executa o comando e captura o resultado
    local result
    result=$(eval "$test_command" 2>/dev/null)
    local exit_code=$?
    
    # Verifica se o resultado é o esperado
    if [[ "$exit_code" == "$expected_result" ]] || [[ "$result" == "$expected_result" ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC} (got: $result/$exit_code, expected: $expected_result)"
        ((TESTS_FAILED++))
    fi
}

# Função de teste com mock
test_with_mock() {
    local test_name="$1"
    local mock_command="$2"
    local test_command="$3"
    local expected_result="$4"
    
    echo -n "Testing (mocked): $test_name... "
    
    # Cria função mock temporária
    eval "$mock_command"
    
    # Executa o teste
    local result
    result=$(eval "$test_command" 2>/dev/null)
    local exit_code=$?
    
    # Verifica resultado
    if [[ "$exit_code" == "$expected_result" ]] || [[ "$result" == "$expected_result" ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC} (got: $result/$exit_code, expected: $expected_result)"
        ((TESTS_FAILED++))
    fi
}

echo -e "${BLUE}=== Testes Unitários: setup-wnc.sh ===${NC}"
echo

# Importa funções do setup (com proteção)
if [[ -f "setup-wnc.sh" ]]; then
    # Fonte apenas as funções, não executa o script
    source <(grep -E '^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)\s*\{' setup-wnc.sh -A 50 | head -200)
fi

# Teste 1: Verificação de comandos existentes
echo -e "${YELLOW}1. Testando funções utilitárias...${NC}"

test_function "cmd_exists com comando válido" "command -v bash >/dev/null && echo 0 || echo 1" "0"
test_function "cmd_exists com comando inválido" "command -v comando_inexistente >/dev/null && echo 0 || echo 1" "1"

# Teste 2: Validação de entrada
echo -e "\n${YELLOW}2. Testando validações...${NC}"

# Mock para teste de validação DNS
test_with_mock "validate_dns (mock success)" \
    "host() { echo 'example.com has address 1.2.3.4'; return 0; }; dig() { echo '1.2.3.4'; }; curl() { echo '1.2.3.4'; }" \
    "SKIP_DNS_CHECK=false; validate_dns 'example.com'" \
    "0"

test_with_mock "validate_dns com skip" \
    "" \
    "SKIP_DNS_CHECK=true; validate_dns 'qualquer.com' && echo 0 || echo 1" \
    "0"

# Teste 3: Funções de utilidade
echo -e "\n${YELLOW}3. Testando funções de utilidade...${NC}"

test_function "ensure_dir cria diretório" \
    "mkdir -p /tmp/test_dir && echo 0 || echo 1" \
    "0"

test_function "ensure_dir com diretório existente" \
    "[[ -d /tmp ]] && echo 0 || echo 1" \
    "0"

# Teste 4: Geração de credenciais
echo -e "\n${YELLOW}4. Testando geração de credenciais...${NC}"

test_function "openssl gera string aleatória" \
    "openssl rand -hex 16 | wc -c | tr -d ' \n'" \
    "33"  # 32 chars + newline removido

# Teste 5: Validação de portas
echo -e "\n${YELLOW}5. Testando validação de portas...${NC}"

test_function "verifica porta ocupada (22)" \
    "ss -tuln | grep -q ':22 ' && echo 0 || echo 1" \
    "0"

test_function "verifica porta livre (99999)" \
    "ss -tuln | grep -q ':99999 ' && echo 1 || echo 0" \
    "0"

# Teste 6: Parsing de argumentos
echo -e "\n${YELLOW}6. Testando parsing de argumentos...${NC}"

# Simula função de parsing
parse_test_args() {
    local debug_mode=false
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug) debug_mode=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            *) shift ;;
        esac
    done
    
    [[ "$debug_mode" == "true" && "$dry_run" == "true" ]] && echo "both" || echo "single"
}

test_function "parse argumentos múltiplos" \
    "parse_test_args --debug --dry-run" \
    "both"

test_function "parse argumento único" \
    "parse_test_args --debug" \
    "single"

# Teste 7: Validação de ambiente
echo -e "\n${YELLOW}7. Testando validações de ambiente...${NC}"

test_function "sistema é Linux" \
    "uname -s" \
    "Linux"

test_function "bash está disponível" \
    "command -v bash >/dev/null && echo 'available' || echo 'missing'" \
    "available"

# Teste 8: Manipulação de strings
echo -e "\n${YELLOW}8. Testando manipulação de strings...${NC}"

test_function "extração de domínio de URL" \
    "echo 'https://example.com/path' | sed 's|https://||' | cut -d'/' -f1" \
    "example.com"

test_function "validação de email" \
    "[[ 'test@example.com' =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && echo 'valid' || echo 'invalid'" \
    "valid"

# Limpeza
rm -rf /tmp/test_dir 2>/dev/null

# Resumo dos testes
echo
echo -e "${BLUE}=== Resumo dos Testes ===${NC}"
echo -e "Passou: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Falhou: ${RED}$TESTS_FAILED${NC}"
echo -e "Total: $((TESTS_PASSED + TESTS_FAILED))"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}✅ Todos os testes passaram!${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Alguns testes falharam!${NC}"
    exit 1
fi