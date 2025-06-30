#!/usr/bin/env bats

@test "wnc-cli sem argumentos exibe ajuda" {
  run ./wnc-cli.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"Uso:"* ]]
}

