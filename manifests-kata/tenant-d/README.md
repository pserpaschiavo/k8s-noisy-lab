# Tenant D - Workloads Sensíveis a CPU e Disco com Kata Containers

Este diretório contém manifestos para o Tenant D, que executa cargas de trabalho sensíveis a CPU e operações de disco (I/O), adaptados para utilizar o runtime Kata Containers.

## Componentes

- **cpu-disk-workload.yaml**: Implementação PostgreSQL com benchmarks PGBench para testar isolamento de CPU e I/O

## Adaptações para Kata Containers

1. Adição de `runtimeClassName: kata` na especificação do pod
2. Configurações otimizadas para melhorar o isolamento de I/O e CPU
3. Jobs de benchmark configurados para avaliar a eficácia do isolamento

## Observações sobre Isolamento de CPU e I/O

O PostgreSQL é sensível tanto a contenções de CPU quanto de I/O, e pode sofrer degradação significativa de desempenho em ambientes com vizinhos barulhentos. Com o Kata Containers:

1. O escalonador de I/O da VM leve deve proporcionar melhor isolamento para operações de disco
2. A contenção de CPU deve ser reduzida graças ao isolamento adicional proporcionado pela camada de virtualização
3. Os benchmarks devem mostrar menor variabilidade e maior estabilidade durante ataques do tenant-b

## Recomendações para Análise

Compare os resultados do pgbench entre contêineres padrão e Kata Containers, especialmente durante os períodos de ataque, para entender quantitativamente o benefício do isolamento aprimorado.
