# Tenant A - Workloads Sensíveis à Rede com Kata Containers

Este diretório contém manifestos para o Tenant A, que hospeda workloads sensíveis à rede, adaptados para utilizar o runtime Kata Containers.

## Componentes

- **nginx-deploy.yaml**: Implantação NGINX configurada para funcionar com Kata Containers, sensível a condições de rede
- Outras cargas de trabalho sensíveis à rede configuradas para isolamento aprimorado

## Adaptações para Kata Containers

1. Adição de `runtimeClassName: kata` na especificação do pod
2. Cabeçalhos HTTP personalizados para indicar a execução em ambiente Kata
3. Configurações de tolerância à latência e timeouts de conexão

## Observações de Desempenho

- O Kata Containers pode introduzir uma pequena sobrecarga no tempo de inicialização do pod
- A latência de rede pode ser ligeiramente maior no Kata Containers em comparação com contêineres regulares
- Observe métricas comparativas no dashboard Grafana específico para Kata Containers
