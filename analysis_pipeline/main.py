### analysis_pipeline/main.py

from data_loader import load_metrics
from stats_summary import summarize_metrics
from correlation_analysis import compute_correlations
from visualizations import plot_all
import os

# Caminho base dos resultados
BASE_DIR = "results/"
EXPERIMENT_NAME = "meu-experimento"
ROUND = "round-1"
PHASES = ["baseline", "attack", "recovery"]


def main():
    for phase in PHASES:
        print(f"\n>>> Analisando fase: {phase.upper()}")

        # Define o caminho para os CSVs
        path = os.path.join(BASE_DIR, EXPERIMENT_NAME, ROUND, phase)

        # Carrega os dados
        df = load_metrics(path)

        # Estatísticas descritivas e estocásticas
        summarize_metrics(df, phase)

        # Análise de correlação
        compute_correlations(df, phase)

        # Visualizações
        plot_all(df, phase)


if __name__ == '__main__':
    main()