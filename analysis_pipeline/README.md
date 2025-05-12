# 📊 analysis_pipeline

Este diretório contém o pipeline completo para análise de métricas coletadas durante os experimentos de "Noisy Neighbours" em ambientes Kubernetes multi-tenant.

## 🔍 O que este pipeline faz

1. Carrega métricas de múltiplos tenants em formato `.csv` recursivamente (incluindo subdiretórios)
2. Realiza análise estatística e estocástica (média, desvio, skew, kurtosis, estacionariedade)
3. Calcula correlações (Pearson e Spearman) e gera heatmaps
4. Gera visualizações (séries temporais e distribuições) com paletas daltônico-friendly
5. Compara métricas entre diferentes fases do experimento (baseline, ataque, recuperação)
6. Organiza análises por categorias/componentes do sistema
7. Organiza tudo de forma modular e fácil de expandir

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

Os seguintes arquivos e análises serão gerados:

- Tabelas estatísticas (impressas no console)
- Heatmaps de correlação: `plots/<fase>/correlacao_pearson.png`
- Séries temporais: `plots/<fase>/serie_temporal_<fonte>.png`
- Métricas por categoria: `plots/<fase>/metricas_<fonte>_<categoria>.png`
- Distribuições: `plots/<fase>/dist_<fonte>_<categoria>.png`
- Gráficos de dispersão para correlações fortes: `plots/<fase>/scatter_<metrica1>_vs_<metrica2>.png`
- Comparações entre fases: `plots/comparacao_fases/boxplot_<metrica>_<categoria>_<fonte>.png`

Todos os resultados são organizados em diretórios estruturados por fase e categoria, facilitando a análise posterior.

## 📋 Funcionalidades adicionadas

- **Processamento recursivo de subdiretórios**: Analisa automaticamente todas as subpastas de métricas
- **Categorização automática**: Usa a estrutura de diretórios para categorizar métricas
- **Análise por componente**: Separa análises por categoria (tenant, ingress, etc.)
- **Metadados enriquecidos**: Adiciona informações de origem e caminho às métricas
- **Detecção de correlações significativas**: Destaca automaticamente correlações fortes
- **Comparação entre fases**: Análise estatística comparativa entre baseline, ataque e recuperação
- **Organização melhorada da saída**: Estrutura de diretórios organizada para os resultados

## 🧠 Expansões possíveis

- Exportar relatórios Markdown ou PDF com todos os resultados
- Adicionar análise de séries temporais (ARIMA, decomposição, etc.)
- Análise de causalidade (ex: Granger)
- Análise de anomalias entre fases do experimento
- Detecção automática de métricas com maiores variações durante ataques

---

## 📄 Licença
MIT