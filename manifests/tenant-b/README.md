# Tenant B - Tenant Barulhento (Noisy Neighbor)

## Descrição
Este tenant atua como o "vizinho barulhento" (noisy neighbor) no experimento. Ele é projetado para consumir recursos de forma agressiva e potencialmente interferir no desempenho de outros tenants no mesmo cluster.

## Características
- Geração intensiva de tráfego de rede através do `traffic-generator` e `traffic-server`
- Consumo intenso de CPU usando `stress-ng`
- Servidor iperf para testes de largura de banda
- Concebido para simular cargas de trabalho não otimizadas ou maliciosas

## Componentes
- **traffic-generator**: Gera tráfego HTTP contínuo para o traffic-server
- **traffic-server**: Serve conteúdo estático de diferentes tamanhos para simular carga de rede
- **stress-ng**: Ferramenta que gera carga de CPU e memória intensa
- **iperf-server**: Servidor para testes de largura de banda de rede

## Métricas importantes para monitorar
- `cpu_usage`: Utilização de CPU
- `memory_usage`: Utilização de memória
- `network_transmit` e `network_receive`: Tráfego de rede
- `resource_dominance_index`: Indica quanto este tenant está dominando os recursos do cluster
- `cpu_throttled_ratio`: Taxa de throttling de CPU (indica contenção de recursos)

## Impacto esperado durante experimento
Durante a fase de ataque, este tenant deverá causar:
- Degradação de desempenho no tenant-a (sensível à rede)
- Pressão de memória no tenant-c (sensível à memória)
- Contenção de CPU e disco no tenant-d (sensível a CPU e disco)

O objetivo é avaliar a eficácia das políticas de QoS e isolamento em um ambiente Kubernetes sob condições de contenção de recursos.