# Tenant B - "Noisy Neighbors" com Kata Containers

Este diretório contém manifestos para o Tenant B, que executa cargas de trabalho de "vizinhos barulhentos" (noisy neighbors), adaptados para utilizar o runtime Kata Containers.

## Componentes

- **stress-ng.yml**: Workload que gera estresse de CPU e memória
- **traffic-generator.yaml**: Gerador de tráfego intensivo para testes de rede
- **traffic-server.yaml**: Servidor web para receber o tráfego de teste

## Adaptações para Kata Containers

1. Adição de `runtimeClassName: kata` na especificação do pod
2. Configurações otimizadas para isolar os efeitos de vizinhos barulhentos
3. Cabeçalhos e métricas específicos para monitoramento do impacto do isolamento Kata

## Cenários de Teste

Este tenant é propositadamente configurado para criar condições de "vizinhos barulhentos". Quando executado com Kata Containers, deve-se observar:

1. Menor impacto nas cargas de trabalho de outros tenants devido ao isolamento aprimorado
2. Maior contenção dos recursos utilizados dentro da própria VM leve do Kata
3. Diferenças quantificáveis em métricas de desempenho entre implementações com e sem Kata Containers
