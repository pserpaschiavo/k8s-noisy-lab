# Tenant C - Workloads Sensíveis à Memória com Kata Containers

Este diretório contém manifestos para o Tenant C, que executa cargas de trabalho sensíveis à memória, adaptados para utilizar o runtime Kata Containers.

## Componentes

- **memory-workload.yaml**: Implementação Redis com benchmarks para testar isolamento de memória

## Adaptações para Kata Containers

1. Adição de `runtimeClassName: kata` na especificação do pod
2. Configurações otimizadas para isolar o consumo de memória e evitar interferência
3. Benchmarks para avaliar o impacto do isolamento em operações de memória intensivas

## Observações sobre Isolamento de Memória

O Redis é particularmente sensível a contenções de memória e pode sofrer degradação significativa quando compartilha recursos com vizinhos barulhentos. Com o Kata Containers:

1. Espera-se que o impacto do vazamento de memória e cache thrashing seja reduzido
2. As operações de alocação e liberação de memória devem sofrer menos interferência
3. O benchmark deve mostrar maior estabilidade de desempenho durante ataques de tenant-b
