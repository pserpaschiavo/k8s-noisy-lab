# Kata Containers

## Introdução

Kata Containers é uma tecnologia de isolamento avançada que combina a velocidade dos containers com o isolamento das máquinas virtuais. Este documento descreve a integração do Kata Containers no ambiente de laboratório para experimentos de "Noisy Neighbors" em Kubernetes.

## Integração com o Minikube

O laboratório agora suporta dois modos de execução:
1. **Modo Regular**: Utiliza o runtime padrão do Kubernetes (containerd + runc)
2. **Modo Kata Containers**: Utiliza o runtime Kata Containers para maior isolamento

### Uniformização das Configurações

Para garantir comparações justas, os ambientes foram uniformizados:

- **CNI**: Ambos os ambientes usam Flannel como plugin CNI padrão
- **Container Runtime**: Ambos usam containerd como runtime de containers
- **Parâmetros do Minikube**: Mesmas configurações para CPU, memória e versão do Kubernetes

## Scripts de Configuração

### setup-minikube.sh

Configura um cluster Kubernetes padrão com o Minikube.

```bash
./setup-minikube.sh [opções]
```

**Opções:**
- `--cpus NUM`: Define o número de CPUs (padrão: 8)
- `--memory SIZE`: Define a quantidade de memória (padrão: 16g)
- `--disk SIZE`: Define o tamanho do disco (padrão: 40g)
- `--cni PLUGIN`: Define o CNI (padrão: flannel)
- `--k8s-version VERSION`: Define a versão do Kubernetes (padrão: v1.32.0)

### setup-kata-containers.sh

Configura um cluster Kubernetes com Kata Containers.

```bash
./setup-kata-containers.sh [opções]
```

**Opções:**
- `--cpus NUM`: Define o número de CPUs (padrão: 8)
- `--memory SIZE`: Define a quantidade de memória (padrão: 16g)
- `--disk SIZE`: Define o tamanho do disco (padrão: 40g)
- `--cni PLUGIN`: Define o CNI (padrão: flannel)
- `--k8s-version VERSION`: Define a versão do Kubernetes (padrão: v1.32.0)
- `--manual-setup`: Usa instalação manual em vez do kata-deploy

## Experimentos de Isolamento

### Comparação de Isolamentos

O script `compare-isolations.sh` permite comparar o desempenho entre os dois ambientes:

```bash
./compare-isolations.sh --standard --kata
```

Este script:
1. Implanta workloads nos dois ambientes
2. Executa fases de baseline, ataque e recuperação
3. Coleta métricas de desempenho
4. Gera relatórios comparativos

### Como Executar Experimentos

Para um ciclo completo de testes:

```bash
# Configurar ambiente padrão e executar experimentos
./setup-minikube.sh
./run-experiment.sh

# Configurar ambiente Kata e executar experimentos
./setup-kata-containers.sh
./run-kata-experiment.sh

# Comparar os resultados
./compare-isolations.sh --generate-report
```

## Resultados e Análise

Os resultados dos experimentos são salvos em `/home/phil/Projects/k8s-noisy-lab/results/` organizados por data e hora.

### Diferenças Esperadas

Ao comparar os dois ambientes, deve-se observar:

1. **Menor impacto de "noisy neighbors"** no ambiente Kata Containers
2. **Maior isolamento de recursos** entre os tenants no ambiente Kata
3. **Possível aumento de overhead** em termos de inicialização e uso de memória no ambiente Kata
4. **Diferenças mais evidentes** em workloads sensíveis a CPU e memória

### Limitações

- A virtualização aninhada (necessária para Kata Containers) pode estar limitada em alguns ambientes
- Operações de entrada/saída podem ter overhead adicional em Kata Containers
- Nem todos os recursos Kubernetes têm comportamento idêntico nos dois ambientes

## Conclusão

A integração do Kata Containers, juntamente com a padronização do CNI para Flannel em ambos os ambientes, fornece um cenário mais controlado e justo para avaliar o impacto de diferentes tecnologias de isolamento em cenários de "Noisy Neighbors" no Kubernetes.
