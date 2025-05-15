# Migração para Flannel CNI

## Visão Geral da Mudança

Este documento descreve a migração do CNI (Container Network Interface) do Calico para o Flannel em toda a infraestrutura do laboratório de experimentos. Esta mudança foi implementada para garantir maior compatibilidade e consistência entre os ambientes regulares de Kubernetes e os ambientes que utilizam Kata Containers.

## Motivação

A migração para Flannel foi motivada pelos seguintes fatores:

1. **Compatibilidade com Kata Containers**: O Flannel demonstra melhor compatibilidade com Kata Containers e sua abordagem de virtualização aninhada.

2. **Consistência entre ambientes**: Manter o mesmo CNI em ambos os ambientes (regular e Kata Containers) minimiza variáveis nos experimentos de isolamento.

3. **Simplicidade**: O Flannel oferece uma solução de rede mais simples e leve, que é adequada para o ambiente de laboratório.

4. **Desempenho com virtualização aninhada**: Flannel funciona melhor em cenários onde a virtualização aninhada é utilizada (caso do Kata Containers).

## Alterações Realizadas

### 1. Script `setup-minikube.sh`

O script original do Minikube foi alterado para usar Flannel como CNI padrão, em vez de Calico:

```bash
# Configuração antiga
--cni=calico \

# Nova configuração
--cni=flannel \
```

Também foi adicionada a opção de personalizar o CNI via linha de comando:

```bash
--cni PLUGIN           Define o CNI a ser usado (padrão: flannel, opções: flannel, calico, cilium)
```

### 2. Script `setup-kata-containers.sh`

O script Kata Containers já utilizava Flannel como padrão, mas foram feitas melhorias para garantir maior flexibilidade e detecção de problemas:

```bash
CNI_PLUGIN="flannel"    # CNI compatível com Kata Containers

# Opção adicionada aos parâmetros
--cni PLUGIN           Define o CNI a ser usado (padrão: flannel, opções: flannel, cilium)
```

## Como Testar os Ambientes

Para garantir que ambos os ambientes estejam funcionando corretamente com o novo CNI, execute:

### Para o ambiente regular:
```bash
./setup-minikube.sh
./check-cluster.sh
```

### Para o ambiente com Kata Containers:
```bash
./setup-kata-containers.sh
./check-cluster.sh
```

## Potenciais Problemas e Soluções

### Conectividade entre Pods
Se houver problemas de conectividade entre pods após a migração:

```bash
# Verifique o status do CNI
kubectl get pods -n kube-system | grep flannel

# Verifique os logs do CNI
kubectl logs -n kube-system $(kubectl get pods -n kube-system | grep flannel | head -n 1 | awk '{print $1}')
```

### Compatibilidade com Network Policies
O Flannel não oferece suporte nativo a Network Policies. Se o seu ambiente depender fortemente dessas políticas, considere:

1. Usar Calico para casos específicos:
```bash
./setup-minikube.sh --cni=calico
```

2. Combinar Flannel com outras soluções para Network Policies

## Impacto nos Experimentos

Esta alteração garante que os experimentos de "Noisy Neighbors" sejam realizados em ambientes mais comparáveis, reduzindo variáveis relacionadas à rede. Ao usar o mesmo CNI em ambos os cenários, podemos ter maior confiança que as diferenças observadas são devidas às tecnologias de isolamento (como Kata Containers) e não a diferenças nas implementações de rede.

## Referências

- [Documentação do Flannel](https://github.com/flannel-io/flannel)
- [Kata Containers Networking](https://github.com/kata-containers/kata-containers/blob/main/docs/networking.md)
- [Minikube CNI](https://minikube.sigs.k8s.io/docs/handbook/network_policy/)
