# Tenant D - Sensível a CPU e Disco

## Descrição
Este tenant foi projetado para ser sensível tanto à utilização de CPU quanto ao desempenho de disco. Ele representa aplicações como bancos de dados transacionais, sistemas de processamento batch, ou serviços de análise que dependem de CPU previsível e bom desempenho de I/O.

## Características
- Executa cargas de trabalho com uso intensivo de CPU
- Realiza operações frequentes de leitura/escrita em disco
- Potencialmente inclui um banco de dados PostgreSQL
- Sensível a problemas como:
  - Throttling de CPU
  - Contenção de I/O
  - Latência elevada em operações de disco
  - Variações na velocidade de processamento (jitter)

## Métricas importantes para monitorar
- `cpu_usage`: Utilização total de CPU
- `cpu_throttled_time`: Tempo em que a CPU foi limitada
- `disk_io_total`: Total de operações de I/O por segundo
- `disk_throughput_total`: Taxa de transferência total em disco (bytes/s)
- `disk_io_tenant_d`: I/O de disco por container
- `postgres_disk_io`: I/O específico do PostgreSQL (se aplicável)
- `postgres_connections`: Número de conexões ativas com o banco de dados
- `postgres_transactions`: Taxa de transações por segundo

## Impacto esperado durante experimento
Durante a fase de ataque pelo tenant-b (barulhento), espera-se observar:
- Aumento no tempo de throttling de CPU
- Redução no desempenho de I/O de disco
- Aumento na latência de transações do banco de dados
- Possível instabilidade em aplicações sensíveis a timing

Este tenant permite avaliar o impacto de contenção de recursos computacionais e de I/O em ambientes multi-tenant, bem como a eficácia das políticas de QoS na proteção desses workloads.