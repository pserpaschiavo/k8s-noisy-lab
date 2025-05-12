### analysis_pipeline/main.py

from data_loader import load_metrics
from stats_summary import summarize_metrics
from correlation_analysis import compute_correlations
from visualizations import plot_all
import os
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np

# Caminho base dos resultados
BASE_DIR = os.getenv("K8S_NOISY_LAB_ROOT", os.path.abspath(os.path.dirname(__file__) + "/.."))
RESULTS_DIR = os.path.join(BASE_DIR, "results")
EXPERIMENT_NAME = "2025-05-11/16-58-00/default-experiment-1"
ROUND = "round-1"
PHASES = ["1 - Baseline", "2 - Attack", "3 - Recovery"]


def compare_phases(all_data):
    """
    Realiza análise comparativa entre as diferentes fases do experimento.
    """
    print("\n>>> ANÁLISE COMPARATIVA ENTRE FASES")
    
    # Cria diretório para salvar os gráficos de comparação entre fases
    plots_dir = os.path.join("plots", "comparacao_fases")
    os.makedirs(plots_dir, exist_ok=True)
    
    # Obtém todas as categorias em todos os dataframes
    all_categories = set()
    for phase, df in all_data.items():
        if '__category__' in df.columns:
            all_categories.update(df['__category__'].unique())
    
    all_categories.discard('')  # Remove categoria vazia
    
    # Para cada categoria, compara as métricas ao longo das fases
    for category in all_categories:
        print(f"\n--- Comparando categoria: {category} ---")
        
        # Coletamos dados para esta categoria em todas as fases
        category_data = {}
        common_sources = None
        
        for phase, df in all_data.items():
            # Filtra apenas dados desta categoria
            if '__category__' in df.columns:
                cat_df = df[df['__category__'] == category]
                if len(cat_df) > 0:
                    category_data[phase] = cat_df
                    # Encontra fontes comuns a todas as fases
                    if common_sources is None:
                        common_sources = set(cat_df['__source__'].unique())
                    else:
                        common_sources &= set(cat_df['__source__'].unique())
        
        # Se temos dados para esta categoria em pelo menos duas fases
        if len(category_data) >= 2:
            # Para cada fonte comum
            for source in (common_sources or []):
                print(f"  Analisando fonte: {source}")
                
                # Seleciona métricas numéricas comuns a todas as fases
                common_metrics = None
                for phase, cat_df in category_data.items():
                    src_df = cat_df[cat_df['__source__'] == source]
                    numeric_cols = src_df.select_dtypes(include=[np.number]).columns
                    exclude_cols = ['__category__', '__path__']
                    metrics = [col for col in numeric_cols if col not in exclude_cols]
                    
                    if common_metrics is None:
                        common_metrics = set(metrics)
                    else:
                        common_metrics &= set(metrics)
                
                if not common_metrics:
                    print("    Nenhuma métrica comum encontrada")
                    continue
                
                # Para cada métrica, plota comparação entre fases
                for metric in common_metrics:
                    phase_values = {}
                    
                    for phase, cat_df in category_data.items():
                        src_df = cat_df[cat_df['__source__'] == source]
                        if metric in src_df.columns:
                            phase_values[phase] = src_df[metric].dropna().tolist()
                    
                    if len(phase_values) >= 2:  # Precisa de pelo menos 2 fases para comparar
                        print(f"    Comparando métrica: {metric}")
                        
                        # Boxplot para comparar distribuições entre fases
                        plt.figure(figsize=(12, 6))
                        data_to_plot = []
                        labels = []
                        
                        for phase, values in phase_values.items():
                            if values:  # Só incluir se tiver valores
                                data_to_plot.append(values)
                                labels.append(phase)
                        
                        if data_to_plot:
                            plt.boxplot(data_to_plot, labels=labels)
                            plt.title(f"Comparação de {metric} ({category}/{source})")
                            plt.ylabel(metric)
                            plt.grid(True, alpha=0.3)
                            plt.tight_layout()
                            clean_metric = metric[:30].replace(" ", "_").replace("/", "_")
                            clean_source = source[:20].replace(" ", "_").replace("/", "_")
                            clean_category = category[:20].replace(" ", "_").replace("/", "_")
                            plt.savefig(f"{plots_dir}/boxplot_{clean_metric}_{clean_category}_{clean_source}.png", dpi=120)
                            plt.close()
                            
                            # Estatísticas básicas
                            print(f"      Estatísticas por fase:")
                            for i, phase in enumerate(labels):
                                values = data_to_plot[i]
                                if len(values) > 0:
                                    print(f"        {phase}: média={np.mean(values):.2f}, mediana={np.median(values):.2f}, min={np.min(values):.2f}, max={np.max(values):.2f}")
                    else:
                        print(f"    Dados insuficientes para a métrica {metric}")


def main():
    all_data = {}  # Armazenar dados de todas as fases para análise comparativa

    for phase in PHASES:
        print(f"\n>>> Analisando fase: {phase.upper()}")

        # Define o caminho para os CSVs
        path = os.path.join(RESULTS_DIR, EXPERIMENT_NAME, ROUND, phase)

        # Carrega os dados
        print(f"Carregando dados de {path}...")
        df = load_metrics(path)
        all_data[phase] = df
        
        # Obtém categorias únicas (subpastas)
        categories = df['__category__'].unique()
        print(f"\nCategorias encontradas: {', '.join(categories)}")
        
        # Estatísticas gerais para toda a fase
        print("\n--- ANÁLISE GERAL DA FASE ---")
        summarize_metrics(df, f"{phase} (geral)")
        
        # Análise por categoria
        for category in categories:
            if category == '':  # Pula entradas sem categoria
                continue
                
            print(f"\n--- ANÁLISE DA CATEGORIA: {category} ---")
            category_df = df[df['__category__'] == category]
            
            # Estatísticas por categoria
            summarize_metrics(category_df, f"{phase}/{category}")
            
            # Análise de correlação por categoria
            compute_correlations(category_df, f"{phase}/{category}")
            
            # Visualizações por categoria
            plot_all(category_df, f"{phase}/{category}")
        
        # Análise de correlação geral
        print("\n--- CORRELAÇÕES GERAIS ---")
        compute_correlations(df, phase)
        
        # Visualizações gerais
        print("\n--- VISUALIZAÇÕES GERAIS ---")
        plot_all(df, phase)
        
    # Análise comparativa entre fases
    if len(all_data) == len(PHASES):
        compare_phases(all_data)


if __name__ == '__main__':
    main()