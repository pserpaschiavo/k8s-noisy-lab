# Tenant C - Sensível à Memória

## Descrição
Este tenant é projetado para ser sensível ao uso de memória. Ele representa aplicações que dependem fortemente de ter memória suficiente disponível para operar corretamente, como bancos de dados em memória, sistemas de cache ou aplicações de análise de dados.

## Características
- Cargas de trabalho com uso intensivo de memória
- Suscetível a problemas como:
  - Pressão de memória no nó
  - Troca excessiva (swapping)
  - Eventos de OOM (Out Of Memory)
  - Garbage collection intenso

## Métricas importantes para monitorar
- `memory_usage`: Uso total de memória
- `memory_pressure`: Relação entre memória usada e limite configurado
- `memory_growth_rate`: Taxa de crescimento do uso de memória
- `memory_oomkill_events`: Contagem de eventos de OOMKilled
- `pod_restarts`: Reinícios de pods (possivelmente devido a problemas de memória)

## Impacto esperado durante experimento
Durante a fase de ataque pelo tenant-b (barulhento), espera-se observar:
- Aumento na pressão de memória
- Potencial aumento na taxa de eventos OOMKilled
- Possível redução no desempenho geral devido a garbage collection mais frequente
- Em casos extremos, reinícios de pods por falta de memória

A análise desse tenant permite avaliar como as políticas de limite e reserva de memória em Kubernetes protegem (ou não) cargas de trabalho sensíveis a memória de vizinhos barulhentos.