### analysis_pipeline/time_series_analysis.py

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import os
import statsmodels.api as sm
from statsmodels.tsa.stattools import grangercausalitytests, ccf
from scipy import signal
from scipy.stats import entropy
import seaborn as sns


def compute_cross_correlation(x, y, maxlags=None, plot=True, phase=None, output_dir="plots/time_series_analysis"):
    """
    Calcula e plota a correlação cruzada entre duas séries temporais.
    
    Args:
        x: Primeira série temporal (array-like)
        y: Segunda série temporal (array-like)
        maxlags: Número máximo de lags para calcular (default: None, usa min(len(x)//2, 10))
        plot: Se True, gera e salva um gráfico
        phase: Nome da fase para identificar os arquivos de saída
        output_dir: Diretório para salvar os gráficos
        
    Returns:
        DataFrame com os resultados de correlação cruzada
    """
    # Remover NaN das séries
    x = np.array(pd.Series(x).dropna())
    y = np.array(pd.Series(y).dropna())
    
    # Ajustar comprimentos se necessário para séries de tamanhos diferentes
    min_length = min(len(x), len(y))
    x = x[:min_length]
    y = y[:min_length]
    
    if len(x) < 3 or len(y) < 3:
        print("Séries muito curtas para análise de correlação cruzada.")
        return None
    
    # Definir maxlags se não especificado
    if maxlags is None:
        maxlags = min(len(x) // 2, 10)
    
    # Calcular a correlação cruzada
    cross_corr = ccf(x, y, adjusted=False)
    lags = np.arange(-maxlags, maxlags + 1)
    cross_corr = cross_corr[max(0, len(cross_corr)//2 - maxlags):min(len(cross_corr), len(cross_corr)//2 + maxlags + 1)]
    
    # Verificar se os tamanhos são compatíveis
    if len(lags) > len(cross_corr):
        lags = lags[:len(cross_corr)]
    elif len(lags) < len(cross_corr):
        cross_corr = cross_corr[:len(lags)]
    
    # Criar DataFrame com os resultados
    results_df = pd.DataFrame({
        'lag': lags,
        'cross_correlation': cross_corr
    })
    
    # Encontrar o lag com maior correlação (tratando valores NaN)
    try:
        # Primeiramente verifica se há algum valor não-NaN
        if results_df['cross_correlation'].notna().any():
            # Usa idxmax apenas nos valores não-NaN
            best_idx = results_df['cross_correlation'].abs().fillna(0).idxmax()
            best_lag = results_df.iloc[best_idx]
            print(f"Lag com maior correlação: {best_lag['lag']} (r = {best_lag['cross_correlation']:.3f})")
        else:
            print("Todos os valores de correlação cruzada são NaN.")
            best_lag = pd.Series({'lag': 0, 'cross_correlation': np.nan})
    except Exception as e:
        print(f"Erro ao determinar o lag com maior correlação: {str(e)}")
        best_lag = pd.Series({'lag': 0, 'cross_correlation': np.nan})
    
    # Plotar os resultados
    if plot:
        os.makedirs(output_dir, exist_ok=True)
        
        plt.figure(figsize=(12, 6))
        plt.stem(results_df['lag'], results_df['cross_correlation'])  # Removido parâmetro use_line_collection=True
        plt.axhline(y=0, linestyle='--', color='gray', alpha=0.7)
        plt.axhline(y=0.2, linestyle=':', color='red', alpha=0.4)
        plt.axhline(y=-0.2, linestyle=':', color='red', alpha=0.4)
        plt.grid(True, alpha=0.3)
        plt.title(f'Correlação Cruzada vs. Lag')
        plt.xlabel('Lag')
        plt.ylabel('Correlação Cruzada')
        
        # Destacar o lag com maior correlação apenas se não for NaN
        if not np.isnan(best_lag['cross_correlation']):
            plt.plot(best_lag['lag'], best_lag['cross_correlation'], 'ro', 
                    markersize=8, label=f'Melhor Lag: {best_lag["lag"]}')
            plt.legend()
        
        if phase:
            clean_phase = phase.replace(" ", "_").replace("/", "_")
            plt.tight_layout()
            plt.savefig(f"{output_dir}/cross_corr_{clean_phase}.png", dpi=120)
            plt.close()
        
    return results_df


def lag_analysis(x, y, x_label, y_label, max_lag=10, phase=None, 
                output_dir="plots/time_series_analysis"):
    """
    Realiza análise de lag entre duas séries temporais e plota as séries sobrepostas
    com indicação do lag ótimo.
    
    Args:
        x: Primeira série temporal (array-like)
        y: Segunda série temporal (array-like)
        x_label: Nome/rótulo da primeira série
        y_label: Nome/rótulo da segunda série
        max_lag: Número máximo de lags para testar
        phase: Nome da fase para identificar os arquivos de saída
        output_dir: Diretório para salvar os gráficos
        
    Returns:
        Tupla com (melhor_lag, correlação_máxima)
    """
    # Remover NaN das séries
    x_clean = np.array(pd.Series(x).dropna())
    y_clean = np.array(pd.Series(y).dropna())
    
    # Ajustar comprimentos se necessário
    min_length = min(len(x_clean), len(y_clean))
    x_clean = x_clean[:min_length]
    y_clean = y_clean[:min_length]
    
    if len(x_clean) < max_lag + 1 or len(y_clean) < max_lag + 1:
        print("Séries muito curtas para análise de lag.")
        return None, None
    
    # Normalizar as séries para melhor comparação visual
    x_norm = (x_clean - np.mean(x_clean)) / (np.std(x_clean) if np.std(x_clean) > 0 else 1)
    y_norm = (y_clean - np.mean(y_clean)) / (np.std(y_clean) if np.std(y_clean) > 0 else 1)
    
    # Calcular correlações para diferentes lags
    correlations = []
    for lag in range(-max_lag, max_lag + 1):
        if lag < 0:
            # y está "atrasado" em relação a x
            corr = np.corrcoef(x_norm[:lag], y_norm[-lag:])[0, 1]
        elif lag > 0:
            # x está "atrasado" em relação a y
            corr = np.corrcoef(x_norm[lag:], y_norm[:-lag])[0, 1]
        else:
            # sem lag
            corr = np.corrcoef(x_norm, y_norm)[0, 1]
        
        correlations.append((lag, corr))
    
    # Encontrar o lag com maior correlação (em valor absoluto)
    best_lag, max_corr = max(correlations, key=lambda x: abs(x[1]))
    print(f"Melhor lag entre {x_label} e {y_label}: {best_lag} (r = {max_corr:.3f})")
    
    # Criar gráfico
    os.makedirs(output_dir, exist_ok=True)
    
    plt.figure(figsize=(14, 7))
    
    # Plotar as séries normalizadas
    plt.plot(range(len(x_norm)), x_norm, label=x_label, linewidth=2, alpha=0.7)
    plt.plot(range(len(y_norm)), y_norm, label=y_label, linewidth=2, alpha=0.7)
    
    # Plotar a série y ajustada com o melhor lag
    if best_lag != 0:
        if best_lag < 0:
            # y está "atrasado" em relação a x
            y_adjusted = np.pad(y_norm[-best_lag:], (0, -best_lag), 'constant', constant_values=np.nan)
            shift_direction = f"{y_label} atrás de {x_label}"
        else:
            # x está "atrasado" em relação a y
            y_adjusted = np.pad(y_norm[:-best_lag], (best_lag, 0), 'constant', constant_values=np.nan)
            shift_direction = f"{y_label} à frente de {x_label}"
        
        plt.plot(range(len(y_adjusted)), y_adjusted, label=f"{y_label} (ajustado lag={best_lag})",
                linewidth=1.5, linestyle='--', alpha=0.9)
        
        # Adicionar setas e anotações para o lag
        arrow_pos_x = len(x_norm) // 2
        if best_lag < 0:
            arrow_pos_y = max(y_norm[arrow_pos_x], y_norm[arrow_pos_x - best_lag])
            plt.annotate('', xy=(arrow_pos_x, arrow_pos_y), 
                        xytext=(arrow_pos_x - best_lag, arrow_pos_y),
                        arrowprops=dict(arrowstyle='<->', color='red', lw=1.5))
        else:
            arrow_pos_y = max(y_norm[arrow_pos_x], y_norm[min(len(y_norm)-1, arrow_pos_x + best_lag)])
            plt.annotate('', xy=(arrow_pos_x, arrow_pos_y), 
                        xytext=(arrow_pos_x + best_lag, arrow_pos_y),
                        arrowprops=dict(arrowstyle='<->', color='red', lw=1.5))
        
        plt.annotate(f'Lag = {best_lag}', 
                    xy=(arrow_pos_x, arrow_pos_y), 
                    xytext=(arrow_pos_x, arrow_pos_y + 0.5),
                    ha='center', va='bottom',
                    bbox=dict(boxstyle='round,pad=0.3', fc='yellow', alpha=0.5))
    
    plt.title(f'Análise de Lag: {x_label} vs {y_label} (r = {max_corr:.3f})')
    plt.xlabel('Período de Tempo')
    plt.ylabel('Valor Normalizado')
    plt.grid(True, alpha=0.3)
    plt.legend(loc='best')
    
    if phase:
        clean_x = x_label.replace(" ", "_").replace("/", "_")[:20]
        clean_y = y_label.replace(" ", "_").replace("/", "_")[:20]
        clean_phase = phase.replace(" ", "_").replace("/", "_")
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/lag_analysis_{clean_phase}_{clean_x}_vs_{clean_y}.png", dpi=120)
        plt.close()
    
    return best_lag, max_corr


def granger_causality_test(x, y, x_label, y_label, max_lag=5, phase=None, 
                          output_dir="stats_results"):
    """
    Realiza teste de causalidade de Granger entre duas séries temporais.
    
    Args:
        x: Primeira série temporal (possível causa)
        y: Segunda série temporal (possível efeito)
        x_label: Nome/rótulo da primeira série
        y_label: Nome/rótulo da segunda série
        max_lag: Número máximo de lags para testar
        phase: Nome da fase para identificar os arquivos de saída
        output_dir: Diretório para salvar os resultados
        
    Returns:
        DataFrame com os resultados do teste
    """
    # Remover NaN e garantir que as séries tenham o mesmo tamanho
    xy_data = pd.DataFrame({x_label: x, y_label: y}).dropna()
    
    if len(xy_data) < max_lag + 2:
        print("Séries muito curtas para teste de causalidade de Granger.")
        return None
    
    try:
        # Realizar o teste x -> y (x causa y?)
        xy_results = grangercausalitytests(xy_data[[x_label, y_label]], max_lag, verbose=False)
        
        # Realizar o teste y -> x (y causa x?)
        yx_results = grangercausalitytests(xy_data[[y_label, x_label]], max_lag, verbose=False)
        
        # Extrair p-valores para cada lag
        results = []
        for lag in range(1, max_lag + 1):
            xy_pvalue = xy_results[lag][0]['ssr_ftest'][1]  # p-valor do teste F
            yx_pvalue = yx_results[lag][0]['ssr_ftest'][1]  # p-valor do teste F
            
            results.append({
                'lag': lag,
                f'{x_label} -> {y_label} p-value': xy_pvalue,
                f'{x_label} -> {y_label} significant': xy_pvalue < 0.05,
                f'{y_label} -> {x_label} p-value': yx_pvalue,
                f'{y_label} -> {x_label} significant': yx_pvalue < 0.05
            })
        
        results_df = pd.DataFrame(results)
        
        # Mostrar resumo
        print(f"\nTeste de Causalidade de Granger entre {x_label} e {y_label}:")
        
        # Para a direção x -> y
        min_xy_pvalue = results_df[f'{x_label} -> {y_label} p-value'].min()
        min_xy_lag = results_df.loc[results_df[f'{x_label} -> {y_label} p-value'].idxmin(), 'lag']
        print(f"  {x_label} -> {y_label}: menor p-valor = {min_xy_pvalue:.4f} (lag {min_xy_lag})")
        print(f"  Causalidade significativa: {min_xy_pvalue < 0.05}")
        
        # Para a direção y -> x
        min_yx_pvalue = results_df[f'{y_label} -> {x_label} p-value'].min()
        min_yx_lag = results_df.loc[results_df[f'{y_label} -> {x_label} p-value'].idxmin(), 'lag']
        print(f"  {y_label} -> {x_label}: menor p-valor = {min_yx_pvalue:.4f} (lag {min_yx_lag})")
        print(f"  Causalidade significativa: {min_yx_pvalue < 0.05}")
        
        # Salvar resultados
        if phase:
            os.makedirs(output_dir, exist_ok=True)
            
            clean_x = x_label.replace(" ", "_").replace("/", "_")[:20]
            clean_y = y_label.replace(" ", "_").replace("/", "_")[:20]
            clean_phase = phase.replace(" ", "_").replace("/", "_")
            
            csv_file = f"{output_dir}/granger_{clean_phase}_{clean_x}_vs_{clean_y}.csv"
            tex_file = f"{output_dir}/granger_{clean_phase}_{clean_x}_vs_{clean_y}.tex"
            
            # Salvar como CSV
            results_df.to_csv(csv_file, index=False)
            print(f"Resultados de causalidade Granger salvos em: {csv_file}")
            
            # Salvar como LaTeX
            with open(tex_file, 'w') as f:
                caption = f"Teste de Causalidade de Granger entre {x_label} e {y_label} ({phase})"
                label = f"tab:granger_{clean_phase}_{clean_x}_{clean_y}"
                
                tex_content = results_df.to_latex(
                    index=False,
                    float_format="%.4f",
                    caption=caption,
                    label=label
                )
                f.write(tex_content)
            
            print(f"Resultados de causalidade Granger salvos em: {tex_file}")
        
        return results_df
        
    except Exception as e:
        print(f"Erro no teste de causalidade de Granger: {str(e)}")
        return None


def calculate_entropy(time_series, method='sample', m=2, r=0.2):
    """
    Calcula a entropia de aproximação (ApEn) ou a entropia de amostragem (SampEn) de uma série temporal.
    
    Args:
        time_series: Série temporal para cálculo da entropia
        method: 'sample' para SampEn ou 'approx' para ApEn
        m: Dimensão de incorporação
        r: Tolerância (como fração do desvio padrão)
        
    Returns:
        Valor de entropia calculado
    """
    # Converter para array numpy e remover NaNs
    time_series = np.array(pd.Series(time_series).dropna())
    
    if len(time_series) < m + 2:
        print("Série muito curta para cálculo de entropia.")
        return np.nan
    
    # Normalizar a série
    time_series = (time_series - np.mean(time_series)) / (np.std(time_series) if np.std(time_series) > 0 else 1)
    
    # Calcular a tolerância r como fração do desvio padrão
    tolerance = r
    
    try:
        # Para séries maiores, use a implementação nativa de entropia amostral
        if method == 'sample' and len(time_series) > 5000:
            from entropy import sample_entropy
            return sample_entropy(time_series, m, tolerance)[0]
        
        # Para séries menores ou ApEn, implementação manual:
        N = len(time_series)
        
        # Criar vetores de comparação
        xmi = np.zeros((N - m + 1, m))
        for i in range(N - m + 1):
            xmi[i] = time_series[i:i + m]
        
        # Calcular as distâncias entre todos os vetores
        dist = np.zeros((N - m + 1, N - m + 1))
        for i in range(N - m + 1):
            for j in range(N - m + 1):
                dist[i, j] = np.max(np.abs(xmi[i] - xmi[j]))
        
        # Calcular a contagem de pares próximos para dimensão m
        count_m = np.sum(dist <= tolerance, axis=1)
        
        if method == 'approx':
            # Para ApEn, calcular phi(m) e phi(m+1)
            phi_m = np.sum(np.log(count_m / (N - m + 1))) / (N - m + 1)
            
            # Criar vetores para dimensão m+1
            xm1i = np.zeros((N - m, m + 1))
            for i in range(N - m):
                xm1i[i] = time_series[i:i + m + 1]
            
            # Calcular distâncias para m+1
            dist_m1 = np.zeros((N - m, N - m))
            for i in range(N - m):
                for j in range(N - m):
                    dist_m1[i, j] = np.max(np.abs(xm1i[i] - xm1i[j]))
            
            count_m1 = np.sum(dist_m1 <= tolerance, axis=1)
            phi_m1 = np.sum(np.log(count_m1 / (N - m))) / (N - m)
            
            # ApEn = phi(m) - phi(m+1)
            return abs(phi_m - phi_m1)
        else:
            # Para SampEn, contar auto-matches
            count_self = np.sum(dist == 0, axis=1)
            A = np.sum(count_m) - np.sum(count_self)
            
            # Criar vetores para dimensão m+1
            xm1i = np.zeros((N - m, m + 1))
            for i in range(N - m):
                xm1i[i] = time_series[i:i + m + 1]
            
            # Calcular distâncias para m+1
            dist_m1 = np.zeros((N - m, N - m))
            for i in range(N - m):
                for j in range(N - m):
                    dist_m1[i, j] = np.max(np.abs(xm1i[i] - xm1i[j]))
            
            count_m1 = np.sum(dist_m1 <= tolerance, axis=1)
            count_self_m1 = np.sum(dist_m1 == 0, axis=1)
            B = np.sum(count_m1) - np.sum(count_self_m1)
            
            # SampEn = -log(A/B)
            if B == 0:
                return np.nan
            return -np.log(A / B)
    
    except Exception as e:
        print(f"Erro no cálculo de entropia: {str(e)}")
        return np.nan


def entropy_analysis(data_dict, method='sample', phase=None, 
                    output_dir="plots/time_series_analysis"):
    """
    Realiza análise de entropia para múltiplas séries temporais.
    
    Args:
        data_dict: Dicionário com rótulos como chaves e séries temporais como valores
        method: 'sample' para Entropia Amostral ou 'approx' para Entropia Aproximada
        phase: Nome da fase para identificar os arquivos de saída
        output_dir: Diretório para salvar os gráficos
        
    Returns:
        DataFrame com os resultados de entropia
    """
    # Verificar se há dados suficientes
    if not data_dict:
        print("Nenhum dado fornecido para análise de entropia.")
        return None
    
    results = []
    
    # Calcular a entropia para cada série
    for label, series in data_dict.items():
        # Ignorar séries muito curtas
        if len(pd.Series(series).dropna()) < 4:
            continue
            
        entropy_value = calculate_entropy(series, method=method)
        
        if not np.isnan(entropy_value):
            results.append({
                'label': label,
                'entropy': entropy_value
            })
    
    # Se não houver resultados, retornar None
    if not results:
        print("Não foi possível calcular entropia para nenhuma série.")
        return None
    
    # Criar DataFrame com os resultados
    results_df = pd.DataFrame(results)
    
    # Ordenar por entropia (mais alta para mais baixa)
    results_df = results_df.sort_values('entropy', ascending=False)
    
    # Mostrar resumo
    method_name = "Entropia de Amostragem (SampEn)" if method == 'sample' else "Entropia de Aproximação (ApEn)"
    print(f"\n{method_name} para as séries analisadas:")
    for _, row in results_df.iterrows():
        print(f"  {row['label']}: {row['entropy']:.4f}")
    
    # Criar gráficos
    os.makedirs(output_dir, exist_ok=True)
    
    # Gráfico de barras
    plt.figure(figsize=(12, 6))
    ax = sns.barplot(x='label', y='entropy', data=results_df)
    plt.title(f'{method_name} para diferentes séries')
    plt.xlabel('')
    plt.ylabel('Entropia')
    plt.xticks(rotation=45, ha='right')
    plt.grid(True, axis='y', alpha=0.3)
    
    # Adicionar valores nas barras
    for i, v in enumerate(results_df['entropy']):
        ax.text(i, v + 0.05, f"{v:.3f}", ha='center', fontsize=9)
    
    plt.tight_layout()
    
    if phase:
        clean_phase = phase.replace(" ", "_").replace("/", "_")
        clean_method = "sampEn" if method == 'sample' else "apEn"
        plt.savefig(f"{output_dir}/entropy_bars_{clean_method}_{clean_phase}.png", dpi=120)
    
    plt.close()
    
    # Se tivermos séries temporais de entropia para diferentes pontos/janelas, plotar como série
    if 'window' in results_df.columns:
        plt.figure(figsize=(12, 6))
        for label in results_df['label'].unique():
            label_df = results_df[results_df['label'] == label]
            plt.plot(label_df['window'], label_df['entropy'], marker='o', label=label)
        
        plt.title(f'Evolução da {method_name} ao longo do tempo')
        plt.xlabel('Janela Temporal')
        plt.ylabel('Entropia')
        plt.grid(True, alpha=0.3)
        plt.legend()
        plt.tight_layout()
        
        if phase:
            clean_phase = phase.replace(" ", "_").replace("/", "_")
            clean_method = "sampEn" if method == 'sample' else "apEn"
            plt.savefig(f"{output_dir}/entropy_series_{clean_method}_{clean_phase}.png", dpi=120)
        
        plt.close()
    
    # Salvar os resultados em CSV e LaTeX
    if phase and len(results_df) > 0:
        stats_dir = "stats_results"
        os.makedirs(stats_dir, exist_ok=True)
        
        clean_phase = phase.replace(" ", "_").replace("/", "_")
        clean_method = "sampEn" if method == 'sample' else "apEn"
        
        # Salvar como CSV
        csv_file = f"{stats_dir}/entropy_{clean_method}_{clean_phase}.csv"
        results_df.to_csv(csv_file, index=False)
        print(f"Resultados de entropia salvos em: {csv_file}")
        
        # Salvar como LaTeX
        tex_file = f"{stats_dir}/entropy_{clean_method}_{clean_phase}.tex"
        with open(tex_file, 'w') as f:
            caption = f"{method_name} para diferentes séries temporais ({phase})"
            label = f"tab:entropy_{clean_method}_{clean_phase}"
            
            tex_content = results_df.to_latex(
                index=False,
                float_format="%.4f",
                caption=caption,
                label=label
            )
            f.write(tex_content)
        
        print(f"Resultados de entropia salvos em: {tex_file}")
    
    return results_df


def analyze_metric_pair(x, y, x_label, y_label, phase=None):
    """
    Realiza um conjunto completo de análises para um par de métricas.
    
    Args:
        x: Primeira série temporal
        y: Segunda série temporal
        x_label: Nome/rótulo da primeira série
        y_label: Nome/rótulo da segunda série
        phase: Nome da fase para identificar os arquivos de saída
        
    Returns:
        Dicionário com os resultados das análises
    """
    results = {}
    
    # 1. Calcular correlação cruzada
    print(f"\n=== Análise de correlação cruzada: {x_label} vs. {y_label} ===")
    cc_results = compute_cross_correlation(
        x, y, maxlags=min(10, len(x)//4), plot=True, phase=f"{phase}/{x_label}_vs_{y_label}"
    )
    if cc_results is not None:
        results['cross_correlation'] = cc_results
    
    # 2. Realizar análise de lag
    print(f"\n=== Análise de lag: {x_label} vs. {y_label} ===")
    best_lag, max_corr = lag_analysis(
        x, y, x_label, y_label, max_lag=min(10, len(x)//4), 
        phase=f"{phase}/{x_label}_vs_{y_label}"
    )
    if best_lag is not None:
        results['lag_analysis'] = {'best_lag': best_lag, 'max_correlation': max_corr}
    
    # 3. Teste de causalidade de Granger
    print(f"\n=== Teste de causalidade de Granger: {x_label} vs. {y_label} ===")
    granger_results = granger_causality_test(
        x, y, x_label, y_label, max_lag=min(5, len(x)//5),
        phase=f"{phase}/{x_label}_vs_{y_label}"
    )
    if granger_results is not None:
        results['granger_causality'] = granger_results
    
    return results


def run_time_series_analysis(df, phase, category=None, tenant=None):
    """
    Executa análises de séries temporais em um DataFrame de métricas.
    
    Args:
        df: DataFrame com métricas
        phase: Nome da fase do experimento
        category: Categoria específica para análise (opcional)
        tenant: Tenant específico para análise (opcional)
        
    Returns:
        Dicionário com os resultados das análises
    """
    print(f"\n\n===== ANÁLISE AVANÇADA DE SÉRIES TEMPORAIS =====")
    print(f"Fase: {phase}")
    if category:
        print(f"Categoria: {category}")
    if tenant:
        print(f"Tenant: {tenant}")
    
    # Filtrar DataFrame se categoria ou tenant especificados
    filtered_df = df.copy()
    if category and '__category__' in filtered_df.columns:
        filtered_df = filtered_df[filtered_df['__category__'] == category]
    if tenant and '__source__' in filtered_df.columns:
        sources_with_tenant = [src for src in filtered_df['__source__'].unique() 
                              if tenant.lower() in str(src).lower()]
        if sources_with_tenant:
            filtered_df = filtered_df[filtered_df['__source__'].isin(sources_with_tenant)]
    
    # Obter métricas numéricas
    numeric_cols = filtered_df.select_dtypes(include=[np.number]).columns.tolist()
    
    # Remover colunas de metadados
    exclude_cols = ['__source__', '__category__', '__path__']
    metrics = [col for col in numeric_cols if col not in exclude_cols]
    
    if len(metrics) < 2:
        print("Insuficientes métricas numéricas para análise.")
        return {}
    
    # Selecionar pares de métricas mais promissores para análise
    # (métricas com maior correlação absoluta)
    corr_matrix = filtered_df[metrics].corr()
    
    # Criar pares ordenados por correlação absoluta (excluindo a diagonal)
    pairs = []
    for i, col1 in enumerate(metrics):
        for j, col2 in enumerate(metrics):
            if i < j:  # evitar duplicação
                corr = corr_matrix.loc[col1, col2]
                # Só analisa pares com correlação moderada ou forte
                if abs(corr) >= 0.4:  
                    pairs.append((col1, col2, abs(corr)))
    
    # Ordenar por correlação absoluta (maior primeiro)
    pairs.sort(key=lambda x: x[2], reverse=True)
    
    # Limitar a no máximo 5 pares para não sobrecarregar
    pairs = pairs[:5]
    
    # Preparar resultados
    results = {}
    
    if pairs:
        print(f"\nAnalisando {len(pairs)} pares de métricas com maior correlação:")
        for col1, col2, corr in pairs:
            print(f"  {col1} vs {col2}: r = {corr:.3f}")
            
            # Extrair as séries
            x = filtered_df[col1].values
            y = filtered_df[col2].values
            
            # Realizar análises para o par
            pair_results = analyze_metric_pair(x, y, col1, col2, phase)
            results[f"{col1}_vs_{col2}"] = pair_results
    
    # Análise de entropia para métricas individuais
    print("\n=== Análise de Entropia ===")
    entropy_data = {}
    
    # Agrupar por fonte se disponível
    if '__source__' in filtered_df.columns:
        for source in filtered_df['__source__'].unique():
            source_df = filtered_df[filtered_df['__source__'] == source]
            
            for metric in metrics[:8]:  # Limitar a 8 métricas para não sobrecarregar
                if metric in source_df.columns:
                    values = source_df[metric].values
                    if len(values) >= 10:  # Precisa de um mínimo de pontos
                        label = f"{source}:{metric}"
                        entropy_data[label] = values
    else:
        # Sem fonte, usar métricas diretamente
        for metric in metrics[:10]:
            if metric in filtered_df.columns:
                values = filtered_df[metric].values
                if len(values) >= 10:
                    entropy_data[metric] = values
    
    if entropy_data:
        # Calcular Entropia Amostral (SampEn)
        sampen_results = entropy_analysis(
            entropy_data, method='sample', 
            phase=phase if not category else f"{phase}/{category}"
        )
        if sampen_results is not None:
            results['sample_entropy'] = sampen_results
        
        # Calcular Entropia de Aproximação (ApEn)
        apen_results = entropy_analysis(
            entropy_data, method='approx',
            phase=phase if not category else f"{phase}/{category}"
        )
        if apen_results is not None:
            results['approx_entropy'] = apen_results
    
    return results