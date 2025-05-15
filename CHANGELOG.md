# Alterações no ambiente de laboratório

Data: 14 de maio de 2025

## Resumo das alterações

1. **Migração para Flannel CNI**: Ambos os ambientes (padrão e Kata Containers) agora usam Flannel como CNI padrão para maior consistência nos experimentos.

2. **Melhorias no script de configuração do Kata Containers**:
   - Adicionada instalação via kata-deploy (método recomendado pela equipe do Kata Containers)
   - Melhor detecção de virtualização aninhada
   - Verificação de funcionamento usando pods de teste
   - Parâmetros de linha de comando consistentes com setup-minikube.sh

3. **Parâmetros configuráveis**:
   - Ambos os scripts agora suportam personalização de CPUs, memória, tamanho de disco
   - Opção para escolher o CNI em ambos os scripts
   - Suporte a configurações de recursos limitados

4. **Documentação**:
   - Adicionados documentos sobre a migração do CNI
   - Adicionado guia de uso do Kata Containers

## Próximos passos

1. Validar as alterações em ambientes reais
2. Atualizar documentos sobre resultados dos experimentos
3. Considerar adição de opções para diferentes configurações do Kata Containers

## Observações para testes

Ao testar a nova configuração, verificar especialmente:

- Comunicação de rede entre pods nos diferentes namespaces
- Funcionamento do Kata Containers com Flannel
- Consistência entre ambientes nas métricas de baseline
