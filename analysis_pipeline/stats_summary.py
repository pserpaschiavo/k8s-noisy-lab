## analysis_pipeline/stats_summary.py

import pandas as pd
import numpy as np
import os
from scipy import stats
from statsmodels.tsa.stattools import adfuller


def save_stats_to_csv(stats_df, phase, metrics_type, output_dir="stats_results"):
    """
    Salva um DataFrame de estatísticas em formato CSV.
    
    Args:
        stats_df: DataFrame com estatísticas
        phase: Nome da fase (ex: "baseline", "attack")
        metrics_type: Tipo de métricas (ex: "summary", "stationarity")
        output_dir: Diretório onde salvar os resultados
    """
    os.makedirs(output_dir, exist_ok=True)
    clean_phase = phase.replace("/", "_").replace(" ", "_")
    filename = f"{output_dir}/{clean_phase}_{metrics_type}.csv"
    
    stats_df.to_csv(filename)
    print(f"Estatísticas salvas em CSV: {filename}")
    
    return filename


def save_stats_to_tex(stats_df, phase, metrics_type, output_dir="stats_results"):
    """
    Salva um DataFrame de estatísticas em formato LaTeX (TEX).
    
    Args:
        stats_df: DataFrame com estatísticas
        phase: Nome da fase (ex: "baseline", "attack")
        metrics_type: Tipo de métricas (ex: "summary", "stationarity")
        output_dir: Diretório onde salvar os resultados
    """
    os.makedirs(output_dir, exist_ok=True)
    clean_phase = phase.replace("/", "_").replace(" ", "_")
    filename = f"{output_dir}/{clean_phase}_{metrics_type}.tex"
    
    # Formata números no DataFrame para melhor apresentação no LaTeX
    formatted_df = stats_df.copy()
    for col in formatted_df.select_dtypes(include=[np.number]).columns:
        if formatted_df[col].abs().max() < 0.01:
            # Formato científico para números muito pequenos
            formatted_df[col] = formatted_df[col].map(lambda x: f"{x:.4e}" if not pd.isna(x) else "")
        elif formatted_df[col].abs().max() > 1000:
            # Inteiros para números grandes
            formatted_df[col] = formatted_df[col].map(lambda x: f"{x:.0f}" if not pd.isna(x) else "")
        else:
            # Duas casas decimais para outros números
            formatted_df[col] = formatted_df[col].map(lambda x: f"{x:.2f}" if not pd.isna(x) else "")
    
    # Adiciona título à tabela
    caption = f"Estatísticas de {metrics_type} para a fase {phase}"
    label = f"tab:{clean_phase}_{metrics_type}"
    
    # Gera o código LaTeX
    tex_code = formatted_df.to_latex(
        index=True,
        bold_rows=True,
        caption=caption,
        label=label,
        float_format="%.2f"
    )
    
    # Substitui o cabeçalho padrão do pandas por um mais amigável
    header_line = tex_code.split('\n')[4]
    if "metric" not in header_line.lower():
        # Adiciona 'Metric' como nome da coluna de índice se não estiver presente
        tex_code = tex_code.replace(header_line, header_line.replace("{}", "{Metric}"))
    
    with open(filename, 'w') as f:
        f.write(tex_code)
    
    print(f"Estatísticas salvas em LaTeX: {filename}")
    
    return filename


def summarize_metrics(df, phase, save_results=True):
    print(f"\nResumo estatístico para a fase: {phase}")

    # Remove colunas não numéricas exceto __source__
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    summary = df[numeric_cols].describe(percentiles=[.25, .5, .75])
    print(summary)
    
    # Calcula Skewness e Kurtosis
    print("\nSkewness e Kurtosis:")
    skew_kurt_data = []
    for col in numeric_cols:
        skew = stats.skew(df[col].dropna())
        kurt = stats.kurtosis(df[col].dropna())
        print(f"{col:30} Skew: {skew:.2f}, Kurtosis: {kurt:.2f}")
        skew_kurt_data.append({'metric': col, 'skewness': skew, 'kurtosis': kurt})
    
    skew_kurt_df = pd.DataFrame(skew_kurt_data).set_index('metric')
    
    # Calcula teste de estacionariedade ADF
    print("\nTeste de estacionariedade (ADF):")
    adf_data = []
    for col in numeric_cols:
        try:
            result = adfuller(df[col].dropna())
            print(f"{col:30} ADF p-value: {result[1]:.4f}")
            adf_data.append({
                'metric': col, 
                'adf_stat': result[0], 
                'p_value': result[1],
                'stationary': result[1] < 0.05
            })
        except Exception as e:
            print(f"{col:30} Erro no ADF: {str(e)}")
            adf_data.append({
                'metric': col, 
                'adf_stat': np.nan, 
                'p_value': np.nan,
                'stationary': False
            })
    
    adf_df = pd.DataFrame(adf_data).set_index('metric')
    
    # Salva resultados se solicitado
    if save_results:
        output_dir = "stats_results"
        os.makedirs(output_dir, exist_ok=True)
        
        # Salva estatísticas descritivas
        save_stats_to_csv(summary, phase, "summary", output_dir)
        save_stats_to_tex(summary, phase, "summary", output_dir)
        
        # Salva Skewness e Kurtosis
        save_stats_to_csv(skew_kurt_df, phase, "skewkurt", output_dir)
        save_stats_to_tex(skew_kurt_df, phase, "skewkurt", output_dir)
        
        # Salva resultados ADF
        save_stats_to_csv(adf_df, phase, "adf_test", output_dir)
        save_stats_to_tex(adf_df, phase, "adf_test", output_dir)
        
    return summary, skew_kurt_df, adf_df


def compare_phase_stats(all_stats, save_results=True):
    """
    Compara estatísticas entre diferentes fases e gera tabelas comparativas.
    
    Args:
        all_stats: Dicionário com estatísticas por fase {phase: (summary, skew_kurt, adf)}
        save_results: Se True, salva os resultados em CSV e TEX
        
    Returns:
        Tupla com DataFrames comparativos
    """
    if len(all_stats) < 2:
        print("Insuficientes fases para comparação")
        return None
    
    print("\nComparando estatísticas entre fases...")
    
    # Extrai métricas comuns entre todas as fases
    common_metrics = set()
    first_phase = True
    
    for phase, (summary, _, _) in all_stats.items():
        if first_phase:
            common_metrics = set(summary.columns)
            first_phase = False
        else:
            common_metrics &= set(summary.columns)
    
    if not common_metrics:
        print("Não há métricas comuns entre todas as fases")
        return None
    
    # Compara médias entre fases
    means_comparison = {}
    for phase, (summary, _, _) in all_stats.items():
        means_comparison[phase] = summary.loc['mean'][list(common_metrics)]
    
    means_df = pd.DataFrame(means_comparison)
    print("\nComparação de médias entre fases:")
    print(means_df)
    
    # Compara medianas entre fases
    medians_comparison = {}
    for phase, (summary, _, _) in all_stats.items():
        medians_comparison[phase] = summary.loc['50%'][list(common_metrics)]
    
    medians_df = pd.DataFrame(medians_comparison)
    print("\nComparação de medianas entre fases:")
    print(medians_df)
    
    # Compara desvio padrão entre fases
    std_comparison = {}
    for phase, (summary, _, _) in all_stats.items():
        std_comparison[phase] = summary.loc['std'][list(common_metrics)]
    
    std_df = pd.DataFrame(std_comparison)
    print("\nComparação de desvio padrão entre fases:")
    print(std_df)
    
    # Compara skewness entre fases
    skew_comparison = {}
    for phase, (_, skew_kurt, _) in all_stats.items():
        skew_metrics = set(skew_kurt.index) & common_metrics
        skew_comparison[phase] = skew_kurt.loc[list(skew_metrics)]['skewness']
    
    skew_df = pd.DataFrame(skew_comparison)
    print("\nComparação de skewness entre fases:")
    print(skew_df)
    
    # Salva resultados comparativos
    if save_results:
        output_dir = "stats_results"
        os.makedirs(output_dir, exist_ok=True)
        
        save_stats_to_csv(means_df, "comparison", "means", output_dir)
        save_stats_to_tex(means_df, "comparison", "means", output_dir)
        
        save_stats_to_csv(medians_df, "comparison", "medians", output_dir)
        save_stats_to_tex(medians_df, "comparison", "medians", output_dir)
        
        save_stats_to_csv(std_df, "comparison", "std", output_dir)
        save_stats_to_tex(std_df, "comparison", "std", output_dir)
        
        save_stats_to_csv(skew_df, "comparison", "skewness", output_dir)
        save_stats_to_tex(skew_df, "comparison", "skewness", output_dir)
    
    return means_df, medians_df, std_df, skew_df

