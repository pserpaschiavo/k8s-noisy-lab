# Tenant A - Sensível à Rede

## Descrição
Este tenant é sensível ao desempenho da rede. Ele representa cargas de trabalho que são afetadas por problemas de rede, como latência elevada, perda de pacotes ou congestionamento.

## Características
- Executa um servidor NGINX que depende fortemente do desempenho da rede
- Sensível a problemas como:
  - Perda de pacotes
  - Latência de rede
  - Congestionamento de banda
  - Jitter na conexão

## Métricas importantes para monitorar
- `network_receive`: Taxa de recebimento de bytes
- `network_transmit`: Taxa de transmissão de bytes
- `network_dropped`: Taxa de pacotes descartados
- `network_packet_rate`: Taxa total de pacotes
- `network_error_rate`: Taxa de erros de rede
- `network_efficiency`: Eficiência da rede (bytes por pacote)

## Impacto esperado durante experimento
Durante a fase de ataque pelo tenant-b (barulhento), espera-se observar:
- Aumento na latência de resposta
- Aumento na taxa de pacotes descartados
- Possível redução na eficiência da rede
- Instabilidade na comunicação