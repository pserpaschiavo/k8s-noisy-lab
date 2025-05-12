# 📊 analysis_pipeline

Este diretório contém o pipeline completo para análise de métricas coletadas durante os experimentos de "Noisy Neighbours" em ambientes Kubernetes multi-tenant.

## 🔍 O que este pipeline faz

1. Carrega métricas de múltiplos tenants em formato `.csv` recursivamente (incluindo subdiretórios)
2. Realiza análise estatística e estocástica (média, desvio, skew, kurtosis, estacionariedade)
3. Calcula correlações (Pearson e Spearman) e gera heatmaps
4. Gera visualizações (séries temporais e distribuições) com paletas daltônico-friendly
5. Compara métricas entre diferentes fases do experimento (baseline, ataque, recuperação)
6. Compara métricas entre diferentes tenants para identificar impactos do "noisy neighbor"
7. Exporta tabelas estatísticas em formatos CSV e LaTeX para publicações científicas
8. Organiza análises por categorias/componentes do sistema
9. Organiza tudo de forma modular e fácil de expandir

## 🧰 Requisitos

- Python 3.8+
- Instale as dependências com:

```bash
pip install -r requirements.txt
```

**Requisitos mínimos:**
- pandas
- numpy
- matplotlib
- seaborn
- scipy
- statsmodels

## 📂 Estrutura esperada

O pipeline espera os dados organizados assim:

```
results/
└── YYYY-MM-DD/
    └── HH-MM-SS/
        └── default-experiment-1/
            └── round-1/
                ├── 1 - Baseline/
                │   ├── tenant-a/
                │   │   └── metrics.csv
                │   ├── tenant-b/
                │   ├── ingress-nginx/
                │   └── ...
                ├── 2 - Attack/
                └── 3 - Recovery/
```

O pipeline agora processa recursivamente todos os subdiretórios dentro de cada fase, categorizando as métricas automaticamente com base na estrutura de diretórios.

## 🚀 Como rodar

Edite os valores no `main.py`:

```python
BASE_DIR = os.getenv("K8S_NOISY_LAB_ROOT", os.path.abspath(os.path.dirname(__file__) + "/..")) 
RESULTS_DIR = os.path.join(BASE_DIR, "results")
EXPERIMENT_NAME = "2025-05-11/16-58-00/default-experiment-1"
ROUND = "round-1"
PHASES = ["1 - Baseline", "2 - Attack", "3 - Recovery"]
```

E execute:

```bash
python main.py
```

## 📊 Resultados

### Visualizações Geradas

Os seguintes arquivos e análises gráficas serão gerados:

- **Gráficos Temporais**:
  - Séries temporais: `plots/<fase>/serie_temporal_<fonte>.png`
  - Métricas por categoria: `plots/<fase>/metricas_<fonte>_<categoria>.png`
  - Eixo X com períodos numerados para melhor legibilidade

- **Visualizações de Distribuição**:
  - Distribuições: `plots/<fase>/dist_<fonte>_<categoria>.png`
  - Heatmaps de correlação: `plots/<fase>/correlacao_pearson.png`
  - Gráficos de dispersão para correlações fortes: `plots/<fase>/scatter_<metrica1>_vs_<metrica2>.png`

- **Comparações Entre Fases**:
  - Boxplots: `plots/comparacao_fases/boxplot_<metrica>_<categoria>_<fonte>.png`

- **Comparações Entre Tenants**:
  - Séries temporais: `plots/comparacao_tenants/comp_<fase>_<metrica>.png`
  - Boxplots: `plots/comparacao_tenants/boxplot_<fase>_<metrica>.png`
  - Médias: `plots/comparacao_tenants/media_<fase>_<metrica>.png`

### Tabelas Estatísticas

Além de visualizações, o pipeline agora exporta dados tabulares em formatos CSV e LaTeX:

- **Estatísticas Descritivas**:
  - `stats_results/<fase>_summary.{csv,tex}`: média, mediana, desvio padrão, quartis, etc.

- **Análise de Distribuição**:
  - `stats_results/<fase>_skewkurt.{csv,tex}`: skewness e kurtosis para cada métrica

- **Análise de Estacionariedade**:
  - `stats_results/<fase>_adf_test.{csv,tex}`: resultados do teste ADF (Augmented Dickey-Fuller)

- **Comparações Entre Fases**:
  - `stats_results/comparison_means.{csv,tex}`: comparação das médias entre fases
  - `stats_results/comparison_medians.{csv,tex}`: comparação das medianas entre fases
  - `stats_results/comparison_std.{csv,tex}`: comparação dos desvios padrão entre fases
  - `stats_results/comparison_skewness.{csv,tex}`: comparação da assimetria entre fases

Os arquivos LaTeX podem ser diretamente incorporados em artigos científicos ou relatórios técnicos.

## 🔍 Resultados Esperados

Ao analisar os dados do experimento "Noisy Neighbours", espera-se observar:

1. **Durante a fase de Baseline**:
   - Comportamento estável das métricas de todos os tenants
   - Baixa correlação entre métricas de tenants diferentes
   - Distribuição equilibrada dos recursos do cluster

2. **Durante a fase de Attack**:
   - Aumento significativo no consumo de recursos pelo tenant barulhento (tenant-b)
   - Degradação de desempenho nos tenants sensíveis (tenants a, c, d) evidenciada por:
     - Aumento da latência de resposta no tenant-a (sensível à rede)
     - Aumento do tempo de operação de memória no tenant-c (sensível à memória)
     - Diminuição do throughput de queries no tenant-d (sensível a CPU/disco)
   - Alta correlação entre o consumo de recursos do tenant-b e métricas de degradação dos outros tenants
   - Assimetria (skewness) positiva nas distribuições de métricas de desempenho

3. **Durante a fase de Recovery**:
   - Gradual retorno aos valores de baseline após cessarem as atividades do tenant barulhento
   - Possível persistência de efeitos residuais em alguns componentes do sistema

As tabelas estatísticas e visualizações facilitam a identificação desses padrões e a quantificação precisa do impacto do "noisy neighbor" em cada tipo de workload sensível.

## 📋 Funcionalidades adicionadas

- **Processamento recursivo de subdiretórios**: Analisa automaticamente todas as subpastas de métricas
- **Categorização automática**: Usa a estrutura de diretórios para categorizar métricas
- **Análise por componente**: Separa análises por categoria (tenant, ingress, etc.)
- **Metadados enriquecidos**: Adiciona informações de origem e caminho às métricas
- **Detecção de correlações significativas**: Destaca automaticamente correlações fortes
- **Comparação entre fases**: Análise estatística comparativa entre baseline, ataque e recuperação
- **Comparação entre tenants**: Compara diretamente métricas similares entre diferentes tenants
- **Períodos numerados no eixo X**: Melhora a legibilidade dos gráficos temporais
- **Exportação de tabelas**: Gera tabelas estatísticas em formatos CSV e LaTeX
- **Organização melhorada da saída**: Estrutura de diretórios organizada para os resultados

## 🧠 Expansões possíveis

- Exportar relatórios Markdown ou PDF com todos os resultados
- Adicionar análise de séries temporais (ARIMA, decomposição, etc.)
- Análise de causalidade (ex: Granger)
- Análise de anomalias entre fases do experimento
- Detecção automática de métricas com maiores variações durante ataques
- Implementação de machine learning para detecção automática de "noisy neighbors"

---

## 📄 Licença
MIT