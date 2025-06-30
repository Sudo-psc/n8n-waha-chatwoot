# Processo de Deploy

Este repositório utiliza GitHub Actions para validar os scripts antes de qualquer merge.

1. **Push ou Pull Request** aciona o workflow `CI`.
2. O fluxo instala `shellcheck` e `bats` para analisar e testar os scripts.
3. Todos os arquivos `.sh` são verificados com o `shellcheck`.
4. Os testes em `tests/` são executados com `bats`.
5. Havendo sucesso, o código pode ser implantado manualmente no servidor seguindo as instruções do `README`.

Para produção recomenda-se criar um job separado de deploy que execute os scripts de instalação no servidor.
