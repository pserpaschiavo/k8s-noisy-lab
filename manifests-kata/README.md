# Manifestos para Kata Containers

Este diretório contém versões adaptadas dos manifestos Kubernetes originais configurados para usar o runtime Kata Containers. O Kata Containers é uma tecnologia que combina a segurança de máquinas virtuais com a eficiência de contêineres, proporcionando isolamento avançado para cargas de trabalho em ambientes multi-inquilino.

## Benefícios do Kata Containers

- **Isolamento Fortalecido**: Cada contêiner é executado em uma VM leve dedicada, proporcionando maior isolamento
- **Mitigação de Vizinhos Barulhentos**: Ajuda a reduzir o impacto de "noisy neighbors" em ambientes compartilhados
- **Segurança Melhorada**: Protege contra explorações de escape de contêiner e vulnerabilidades do kernel
- **Compatibilidade OCI**: Funciona com a interface padrão de contêineres sem alterações na API

## Estrutura dos Manifestos

Os manifestos estão organizados por tenant, refletindo a estrutura do diretório `manifests/` original:

- **tenant-a/**: Workloads sensíveis à rede executadas com Kata Containers
- **tenant-b/**: Workloads que geram ruído (noisy neighbors) executadas com Kata Containers
- **tenant-c/**: Workloads sensíveis à memória executadas com Kata Containers
- **tenant-d/**: Workloads sensíveis à CPU e disco executadas com Kata Containers
- **namespace/**: Namespaces para cada tenant com labels adicionais para identificação do runtime

## Diferenças para os Manifestos Originais

As principais alterações nos manifestos Kata Containers em relação aos originais são:

1. Adição da propriedade `runtimeClassName: kata` na especificação do pod
2. Labels adicionais nos namespaces para identificar o uso do Kata Containers
3. Cabeçalhos HTTP adicionais que identificam o runtime para fins de análise
4. Pequenos ajustes para otimizar o desempenho no ambiente de execução do Kata Containers

## Uso em Experimentos

Para usar estes manifestos em experimentos:

1. Certifique-se de que o Kata Containers está configurado no cluster:
   ```bash
   ./setup-kata-containers.sh
   ```

2. Aplique os manifestos específicos para o experimento:
   ```bash
   kubectl apply -f manifests-kata/namespace/tenant-a.yaml
   kubectl apply -f manifests-kata/tenant-a/nginx-deploy.yaml
   ```

3. Para comparar o desempenho entre contêineres regulares e Kata Containers:
   ```bash
   ./compare-isolations.sh
   ```

## Métricas Específicas

Para visualizar métricas específicas do Kata Containers no Grafana, use o dashboard KataContainersDashboard.json localizado em `observability/grafana-dashboards/`.
