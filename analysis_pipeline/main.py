### analysis_pipeline/main.py

from data_loader import load_metrics
from stats_summary import summarize_metrics, compare_phase_stats
from correlation_analysis import compute_correlations
from visualizations import plot_all, plot_tenant_comparison, plot_metrics_by_phase
from time_series_analysis import run_time_series_analysis
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

# Lista opcional de métricas específicas para comparar entre tenants
# Deixe como None para detectar automaticamente as métricas comuns
METRICS_TO_COMPARE = [
    "cpu_usage", 
    "memory_usage", 
    "latency", 
    "requests_per_second",
    "network_in",
    "network_out"
]
# Se None, as métricas comuns serão detectadas automaticamente
# METRICS_TO_COMPARE = None

# Controla quais análises avançadas serão realizadas
ENABLE_ADVANCED_ANALYSIS = True
ANALYZE_CAUSALITY = True  # Análise de causalidade de Granger (pode ser lenta)
ANALYZE_ENTROPY = True    # Análise de entropia (ApEn/SampEn)


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
    all_stats = {}  # Armazenar estatísticas de todas as fases para comparação

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
        phase_stats = summarize_metrics(df, f"{phase} (geral)")
        all_stats[phase] = phase_stats
        
        # Análise por categoria
        for category in categories:
            if category == '':  # Pula entradas sem categoria
                continue
                
            print(f"\n--- ANÁLISE DA CATEGORIA: {category} ---")
            category_df = df[df['__category__'] == category]
            
            # Estatísticas por categoria
            cat_stats = summarize_metrics(category_df, f"{phase}/{category}")
            all_stats[f"{phase}/{category}"] = cat_stats
            
            # Análise de correlação por categoria
            compute_correlations(category_df, f"{phase}/{category}")
            
            # Análises avançadas de séries temporais por categoria
            if ENABLE_ADVANCED_ANALYSIS:
                # Análises específicas para tenants
                if category.startswith('tenant-'):
                    print(f"\n--- ANÁLISE AVANÇADA DE SÉRIE TEMPORAL: {category} ---")
                    run_time_series_analysis(category_df, phase, category=category, 
                                           tenant=category.split('-')[-1])
            
            # Visualizações por categoria
            plot_all(category_df, f"{phase}/{category}")
        
        # Análise de correlação geral
        print("\n--- CORRELAÇÕES GERAIS ---")
        compute_correlations(df, phase)
        
        # Análises avançadas de séries temporais para toda a fase
        if ENABLE_ADVANCED_ANALYSIS:
            print("\n--- ANÁLISE AVANÇADA DE SÉRIE TEMPORAL GERAL ---")
            run_time_series_analysis(df, phase)
        
        # Visualizações gerais
        print("\n--- VISUALIZAÇÕES GERAIS ---")
        plot_all(df, phase)
        
    # Análise comparativa entre fases
    if len(all_data) == len(PHASES):
        compare_phases(all_data)
        
        # Comparação estatística entre fases (tabelas)
        phase_only_stats = {phase: all_stats[phase] for phase in PHASES}
        compare_phase_stats(phase_only_stats)
        
        # Análises avançadas entre fases (Attack vs Baseline)
        if ENABLE_ADVANCED_ANALYSIS and "1 - Baseline" in all_data and "2 - Attack" in all_data:
            print("\n--- ANÁLISE CAUSAL ENTRE FASES: BASELINE vs ATTACK ---")
            
            # Agrupa dados de tenant-b (o barulhento) de ambas as fases
            baseline_df = all_data["1 - Baseline"]
            attack_df = all_data["2 - Attack"]
            
            tenants = ['tenant-a', 'tenant-c', 'tenant-d']
            
            # Analisa o impacto do tenant-b (barulhento) nos outros tenants
            if '__category__' in baseline_df.columns and '__category__' in attack_df.columns:
                
                # Métricas do tenant barulhento (fase de ataque)
                if 'tenant-b' in attack_df['__category__'].unique():
                    noisy_df = attack_df[attack_df['__category__'] == 'tenant-b']
                    
                    # Para cada tenant sensível, analisa o impacto do tenant barulhento
                    for tenant in tenants:
                        if tenant in baseline_df['__category__'].unique() and tenant in attack_df['__category__'].unique():
                            print(f"\n=== Análise de impacto do tenant-b em {tenant} ===")
                            
                            # Dados do tenant sensível em ambas as fases
                            tenant_baseline = baseline_df[baseline_df['__category__'] == tenant]
                            tenant_attack = attack_df[attack_df['__category__'] == tenant]
                            
                            # Encontrar métricas comuns
                            tenant_metrics = tenant_attack.select_dtypes(include=[np.number]).columns
                            tenant_metrics = [col for col in tenant_metrics 
                                           if col not in ['__source__', '__category__', '__path__']]
                            
                            noisy_metrics = noisy_df.select_dtypes(include=[np.number]).columns
                            noisy_metrics = [col for col in noisy_metrics 
                                          if col not in ['__source__', '__category__', '__path__']]
                            
                            # Análise entre métricas do barulhento e métricas sensíveis
                            for noisy_metric in noisy_metrics[:3]:  # Limita para as 3 principais métricas
                                if '__source__' in noisy_df.columns:
                                    for source in noisy_df['__source__'].unique():
                                        source_values = noisy_df[noisy_df['__source__'] == source][noisy_metric].values
                                        if len(source_values) >= 10:
                                            noisy_series = source_values
                                            noisy_label = f"tenant-b:{source}:{noisy_metric}"
                                            
                                            # Encontra métricas correlacionadas do tenant sensível
                                            for tenant_metric in tenant_metrics[:5]:  # Limita para as 5 principais métricas
                                                if '__source__' in tenant_attack.columns:
                                                    for t_source in tenant_attack['__source__'].unique():
                                                        t_values = tenant_attack[tenant_attack['__source__'] == t_source][tenant_metric].values
                                                        if len(t_values) >= 10:
                                                            tenant_series = t_values
                                                            tenant_label = f"{tenant}:{t_source}:{tenant_metric}"
                                                            
                                                            # Executar análise entre as séries
                                                            print(f"Analisando: {noisy_label} -> {tenant_label}")
                                                            
                                                            # Limitar comprimento
                                                            min_len = min(len(noisy_series), len(tenant_series))
                                                            noisy_series = noisy_series[:min_len]
                                                            tenant_series = tenant_series[:min_len]
                                                            
                                                            from time_series_analysis import (
                                                                compute_cross_correlation, 
                                                                lag_analysis,
                                                                granger_causality_test
                                                            )
                                                            
                                                            # Cross-correlation
                                                            compute_cross_correlation(
                                                                noisy_series, tenant_series, 
                                                                maxlags=min(10, min_len//4),
                                                                phase=f"causal_analysis/{noisy_metric}_vs_{tenant_metric}"
                                                            )
                                                            
                                                            # Lag analysis
                                                            lag_analysis(
                                                                noisy_series, tenant_series,
                                                                noisy_label, tenant_label,
                                                                max_lag=min(10, min_len//4),
                                                                phase=f"causal_analysis/{noisy_metric}_vs_{tenant_metric}"
                                                            )
                                                            
                                                            # Granger causality
                                                            if ANALYZE_CAUSALITY:
                                                                granger_causality_test(
                                                                    noisy_series, tenant_series,
                                                                    noisy_label, tenant_label,
                                                                    max_lag=min(5, min_len//5),
                                                                    phase=f"causal_analysis/{noisy_metric}_vs_{tenant_metric}"
                                                                )
        
    # Análise comparativa entre tenants
    print("\n>>> ANÁLISE COMPARATIVA ENTRE TENANTS")
    plot_tenant_comparison(all_data, metrics_to_compare=METRICS_TO_COMPARE)
    
    # Gerar gráficos comparativos por métrica em cada fase
    print("\n>>> GRÁFICOS COMPARATIVOS POR MÉTRICA EM CADA FASE")
    plot_metrics_by_phase(all_data)
    
    print("\n>>> ANÁLISE CONCLUÍDA")
    print(f"Resultados estatísticos salvos no diretório 'stats_results'")
    print(f"Visualizações salvas no diretório 'plots'")
    print(f"Análises de séries temporais salvas no diretório 'plots/time_series_analysis'")


if __name__ == '__main__':
    main()