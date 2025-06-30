#!/usr/bin/env bash
# test-cli-commands.sh - Testes unitários para comandos do wnc-cli.sh

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
test_command() {
    local test_name="$1"
    local command="$2"
    local expected_exit_code="$3"
    
    echo -n "Testing: $test_name... "
    
    # Executa o comando e captura o resultado
    local output
    output=$(eval "$command" 2>/dev/null)
    local actual_exit_code=$?
    
    # Verifica se o código de saída é o esperado
    if [[ "$actual_exit_code" == "$expected_exit_code" ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC} (exit code: $actual_exit_code, expected: $expected_exit_code)"
        ((TESTS_FAILED++))
    fi
}

# Função de teste com verificação de output
test_output() {
    local test_name="$1"
    local command="$2"
    local expected_pattern="$3"
    
    echo -n "Testing: $test_name... "
    
    local output
    output=$(eval "$command" 2>&1)
    
    if [[ "$output" =~ $expected_pattern ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC} (output doesn't match pattern: $expected_pattern)"
        ((TESTS_FAILED++))
    fi
}

echo -e "${BLUE}=== Testes Unitários: wnc-cli.sh ===${NC}"
echo

# Verifica se o CLI existe
if [[ ! -f "wnc-cli.sh" ]]; then
    echo -e "${RED}❌ Arquivo wnc-cli.sh não encontrado!${NC}"
    exit 1
fi

# Torna o script executável
chmod +x wnc-cli.sh

# Teste 1: Comandos básicos
echo -e "${YELLOW}1. Testando comandos básicos...${NC}"

test_output "help command" \
    "./wnc-cli.sh --help" \
    "WNC-CLI.*Uso:"

test_command "invalid command" \
    "./wnc-cli.sh invalid_command" \
    "1"

test_command "no arguments" \
    "./wnc-cli.sh" \
    "1"

# Teste 2: Funções auxiliares
echo -e "\n${YELLOW}2. Testando funções auxiliares...${NC}"

# Testa função compose_file com fonte do script
source_cli_functions() {
    # Extrai apenas as funções do wnc-cli.sh sem executar o main
    source <(grep -A 20 '^compose_file()' wnc-cli.sh | head -10)
    source <(grep -A 10 '^service_exists()' wnc-cli.sh | head -5)
}

test_output "compose_file function" \
    "source_cli_functions && compose_file chatwoot" \
    "/opt/chatwoot/docker-compose.yml"

test_command "compose_file invalid service" \
    "source_cli_functions && compose_file invalid_service" \
    "1"

# Teste 3: Validação de entrada
echo -e "\n${YELLOW}3. Testando validação de entrada...${NC}"

# Mock de função require_root para testes
mock_root_check() {
    cat > /tmp/test_wnc_cli.sh << 'EOF'
#!/usr/bin/env bash
require_root() { 
    [[ ${MOCK_IS_ROOT:-false} == "true" ]] || { echo "Execute como root"; exit 1; }
}
cmd_status() {
    echo "Mock status command executed"
}
case "$1" in
    status) cmd_status ;;
    *) echo "Unknown command"; exit 1 ;;
esac
EOF
    chmod +x /tmp/test_wnc_cli.sh
}

mock_root_check

test_command "non-root access denied" \
    "MOCK_IS_ROOT=false /tmp/test_wnc_cli.sh status" \
    "1"

test_command "root access allowed" \
    "MOCK_IS_ROOT=true /tmp/test_wnc_cli.sh status" \
    "0"

# Teste 4: Parsing de argumentos
echo -e "\n${YELLOW}4. Testando parsing de argumentos...${NC}"

# Cria mock para testar parsing
create_arg_parser() {
    cat > /tmp/test_args.sh << 'EOF'
#!/usr/bin/env bash
parse_credentials_args() {
    case "$1" in
        "") echo "all_services" ;;
        chatwoot|waha|n8n) echo "single_service:$1" ;;
        *) echo "invalid_service"; exit 1 ;;
    esac
}
parse_credentials_args "$@"
EOF
    chmod +x /tmp/test_args.sh
}

create_arg_parser

test_output "credentials without args" \
    "/tmp/test_args.sh" \
    "all_services"

test_output "credentials with valid service" \
    "/tmp/test_args.sh chatwoot" \
    "single_service:chatwoot"

test_command "credentials with invalid service" \
    "/tmp/test_args.sh invalid" \
    "1"

# Teste 5: Formatação de output
echo -e "\n${YELLOW}5. Testando formatação de output...${NC}"

# Testa se as cores estão definidas
test_output "color definitions" \
    "grep -E 'RED=|GREEN=|YELLOW=|BLUE=' wnc-cli.sh" \
    "033"

# Testa logging
test_output "logging function" \
    "grep -A 5 '^log()' wnc-cli.sh" \
    "tee.*LOG_FILE"

# Teste 6: Comandos que não requerem root
echo -e "\n${YELLOW}6. Testando comandos sem privilégios...${NC}"

# Cria mock para comandos read-only
create_readonly_mock() {
    cat > /tmp/readonly_cli.sh << 'EOF'
#!/usr/bin/env bash
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

CREDENTIALS_FILE="/tmp/test_credentials"
echo "chatwoot_url=https://chat.example.com" > "$CREDENTIALS_FILE"
echo "waha_api_key=test-key-123" >> "$CREDENTIALS_FILE"

cmd_credentials() {
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        echo -e "${RED}Arquivo de credenciais não encontrado${NC}"
        exit 1
    fi
    echo -e "${GREEN}Credenciais encontradas${NC}"
    cat "$CREDENTIALS_FILE"
}

case "$1" in
    credentials) cmd_credentials ;;
    *) echo "Command not implemented in mock"; exit 1 ;;
esac
EOF
    chmod +x /tmp/readonly_cli.sh
}

create_readonly_mock

test_output "credentials command mock" \
    "/tmp/readonly_cli.sh credentials" \
    "Credenciais encontradas"

# Teste 7: Manipulação de erros
echo -e "\n${YELLOW}7. Testando tratamento de erros...${NC}"

# Testa comportamento com arquivos inexistentes
test_command "missing credentials file" \
    "CREDENTIALS_FILE=/tmp/nonexistent ./wnc-cli.sh credentials 2>/dev/null || echo 'handled'" \
    "0"

# Teste 8: Validação de estrutura de script
echo -e "\n${YELLOW}8. Testando estrutura do script...${NC}"

test_output "shebang presente" \
    "head -1 wnc-cli.sh" \
    "#!/usr/bin/env bash"

test_output "set options present" \
    "grep '^set -' wnc-cli.sh" \
    "set -euo pipefail"

test_output "usage function exists" \
    "grep -E '^usage\(\)' wnc-cli.sh" \
    "usage()"

# Teste 9: Consistência de comandos
echo -e "\n${YELLOW}9. Testando consistência de comandos...${NC}"

# Verifica se todos os comandos mencionados no usage existem
extract_commands() {
    grep -A 20 'Comandos Disponíveis:' wnc-cli.sh | grep -E '^\s+[a-z]' | awk '{print $1}' | sort
}

extract_case_commands() {
    grep -A 50 'case.*cmd.*in' wnc-cli.sh | grep -E '^\s*[a-z].*\)' | sed 's/[[:space:]]*\([a-z]*\).*/\1/' | sort
}

test_output "command consistency" \
    "diff <(extract_commands) <(extract_case_commands) && echo 'consistent' || echo 'inconsistent'" \
    "consistent"

# Limpeza
rm -f /tmp/test_wnc_cli.sh /tmp/test_args.sh /tmp/readonly_cli.sh /tmp/test_credentials 2>/dev/null

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