# 📊 analysis_pipeline

Este diretório contém o pipeline completo para análise de métricas coletadas durante os experimentos de "Noisy Neighbours" em ambientes Kubernetes multi-tenant.

## 🔍 O que este pipeline faz

1. Carrega métricas de múltiplos tenants em formato `.csv`
2. Realiza análise estatística e estocástica (média, desvio, skew, kurtosis, estacionariedade)
3. Calcula correlações (Pearson e Spearman) e gera heatmaps
4. Gera visualizações (séries temporais e distribuições) com paletas daltônico-friendly
5. Organiza tudo de forma modular e fácil de expandir

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
└── meu-experimento/
    └── round-1/
        ├── baseline/
        │   ├── tenant-a.csv
        │   ├── tenant-b.csv
        │   └── ...
        ├── attack/
        └── recovery/
```

Cada subpasta contém os arquivos CSV das métricas de cada tenant para aquela fase do experimento.

## 🚀 Como rodar

Edite os valores no `main.py`:

```python
EXPERIMENT_NAME = "../k8s-noisy-lab/results/YYYY-MM-DD/HH-MM-SS/experiment-#"       # De preferência o caminho absoluto até o diretório.
ROUND = "round-1"                                                                   # Altere o valor para rounds consequentes.
```

E execute:

```bash
python main.py
```

## 📊 Resultados

Os seguintes arquivos serão gerados:

- Tabelas estatísticas (impressas no console)
- Heatmaps de correlação: `correlation_heatmap_<fase>.png`
- Séries temporais: `plots/serie_temporal_<tenant>_<fase>.png`
- Distribuições: `plots/dist_<tenant>_<métrica>_<fase>.png`

## 🧠 Expansões possíveis

- Exportar relatórios Markdown ou PDF com todos os resultados
- Adicionar análise de séries temporais (ARIMA, decomposição, etc.)
- Análise de causalidade (ex: Granger)

---

## 📄 Licença

MIT. Sinta-se livre para usar, modificar e contribuir!
```