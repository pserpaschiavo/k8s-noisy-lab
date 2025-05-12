### analysis_pipeline/visualizations.py

import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import os
import numpy as np
import matplotlib.dates as mdates
from datetime import datetime
import matplotlib.ticker as ticker


def find_timestamp_column(df):
    """
    Procura uma coluna de timestamp no DataFrame.
    Tenta diferentes nomes comuns e formatos.
    
    Args:
        df: DataFrame pandas com os dados
        
    Returns:
        Nome da coluna de timestamp se encontrada, None caso contrário
    """
    # Lista de possíveis nomes de colunas de timestamp
    time_column_patterns = [
        'time', 'timestamp', 'date', 
        'datetime', 'collection_time', 
        'scrape_time', 'measured_at'
    ]
    
    # Verifica padrões de nome nas colunas
    for col in df.columns:
        col_lower = col.lower()
        if any(pattern in col_lower for pattern in time_column_patterns):
            return col
    
    # Caso especial: tenta converter a primeira coluna numérica para datetime
    # se ela parecer um timestamp ou epoch time
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    if len(numeric_cols) > 0:
        first_numeric = numeric_cols[0]
        sample = df[first_numeric].iloc[0] if len(df) > 0 else None
        
        # Verifica se parece um timestamp unix (valores grandes)
        if sample and sample > 1000000000:  # ~ ano 2001 em timestamp unix
            try:
                # Tenta converter para datetime para ver se faz sentido
                test_date = pd.to_datetime(sample, unit='s')
                if 2000 <= test_date.year <= 2030:  # Faixa plausível
                    return first_numeric
            except:
                pass
    
    return None


def format_time_axis(ax, time_col_data, time_format=None):
    """
    Formata o eixo X para exibir timestamps de maneira legível
    
    Args:
        ax: Eixo matplotlib a formatar
        time_col_data: Dados de timestamp
        time_format: Formato específico de data/hora (opcional)
    """
    if len(time_col_data) == 0:
        return
        
    # Converte para datetime se necessário
    if not pd.api.types.is_datetime64_any_dtype(time_col_data):
        try:
            # Tenta converter de timestamp epoch se for numérico
            if pd.api.types.is_numeric_dtype(time_col_data):
                time_col_data = pd.to_datetime(time_col_data, unit='s')
            else:
                time_col_data = pd.to_datetime(time_col_data)
        except:
            return
    
    # Configura formato do eixo X baseado no intervalo de tempo
    time_range = time_col_data.max() - time_col_data.min()
    
    if time_range.total_seconds() < 300:  # Menos de 5 minutos
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
    elif time_range.total_seconds() < 86400:  # Menos de 1 dia
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
        plt.xticks(rotation=45)
    else:  # Mais de 1 dia
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%m-%d %H:%M'))
        plt.xticks(rotation=45)
        
    # Ajusta o número de ticks para não ficarem amontoados
    ax.xaxis.set_major_locator(mdates.AutoDateLocator(maxticks=10))


def convert_timestamps_to_periods(time_data):
    """
    Converte uma série de timestamps para valores inteiros de período,
    preservando os intervalos relativos entre pontos de tempo.
    
    Args:
        time_data: Série com timestamps
        
    Returns:
        Tupla com: (períodos numerados, dicionário de mapeamento período->timestamp)
    """
    # Garantir que estamos trabalhando com timestamps pandas
    try:
        if not pd.api.types.is_datetime64_any_dtype(time_data):
            if pd.api.types.is_numeric_dtype(time_data):
                time_data = pd.to_datetime(time_data, unit='s')
            else:
                time_data = pd.to_datetime(time_data)
    except:
        # Se falhar na conversão, retorna índices sequenciais
        return list(range(len(time_data))), {}
    
    # Calcular os deltas de tempo relativos ao primeiro timestamp
    if len(time_data) == 0:
        return [], {}
        
    t0 = time_data.min()
    deltas = [(t - t0).total_seconds() for t in time_data]
    
    # Identificar o intervalo mínimo para normalização (evita números muito pequenos)
    if len(deltas) <= 1:
        interval = 1
    else:
        # Calcula a diferença mínima entre timestamps consecutivos
        diff = []
        for i in range(1, len(deltas)):
            if deltas[i] > deltas[i-1]:
                diff.append(deltas[i] - deltas[i-1])
        
        interval = min(diff) if diff else 1
        # Arredonda o intervalo para facilitar a interpretação
        if interval < 1:
            interval = 1
        elif 1 <= interval < 10:
            interval = 1
        elif 10 <= interval < 60:
            interval = 10
        elif 60 <= interval < 300:
            interval = 60  # 1 minuto
        else:
            interval = 300  # 5 minutos
    
    # Converte para períodos numerados com base no intervalo
    periods = [int(round(d / interval)) for d in deltas]
    
    # Cria um mapeamento de período para timestamp para tooltips ou referência
    period_to_time = {p: t for p, t in zip(periods, time_data)}
    
    return periods, period_to_time


def plot_all(df, phase):
    print(f"\nGerando gráficos para a fase: {phase}")

    # Cria diretório para salvar os gráficos, organizados por fase
    plots_dir = os.path.join("plots", phase.replace(" ", "_").replace("/", "_"))
    os.makedirs(plots_dir, exist_ok=True)

    numeric_cols = df.select_dtypes(include=['number']).columns.tolist()
    
    # Procura e remove colunas de timestamp
    time_col = find_timestamp_column(df)
    if time_col and time_col in numeric_cols:
        numeric_cols.remove(time_col)
    
    sources = df['__source__'].unique()
    categories = df['__category__'].unique()

    # Organiza os gráficos por fonte e categoria
    for src in sources:
        src_df = df[df['__source__'] == src]
        
        # Cria um nome de fonte limpo para uso em nomes de arquivo
        clean_src = src.replace(" ", "_").replace("/", "_")
        
        # Serie temporal por fonte, todas as categorias em um gráfico
        if len(src_df) > 1:  # Só plota se houver dados suficientes
            plt.figure(figsize=(14, 6))
            
            # Se tiver coluna de tempo, converte para períodos numerados
            if time_col and time_col in src_df.columns:
                try:
                    # Converte para datetime se necessário e depois para períodos
                    if pd.api.types.is_numeric_dtype(src_df[time_col]):
                        time_data = pd.to_datetime(src_df[time_col], unit='s')
                    else:
                        time_data = pd.to_datetime(src_df[time_col])
                    
                    # Converte timestamps para períodos numerados
                    period_data, period_map = convert_timestamps_to_periods(time_data)
                    
                    x_data = period_data
                    x_label = "Período de coleta"
                    is_period_data = True
                    
                    # Guarda o mapeamento período->timestamp para uso na tooltip
                    period_time_map = period_map
                    
                except Exception as e:
                    print(f"  Erro ao converter timestamps para períodos: {str(e)}")
                    # Fallback para índices sequenciais
                    x_data = range(len(src_df))
                    x_label = "Índice (ordem sequencial de coleta)"
                    is_period_data = False
            else:
                # Se não tiver coluna de tempo, usa o índice
                x_data = range(len(src_df))
                x_label = "Índice (ordem sequencial de coleta)"
                is_period_data = False
            
            fig, ax = plt.subplots(figsize=(14, 6))
            
            # Para cada categoria, plotar como uma linha diferente
            for cat in categories:
                if cat == '':
                    continue
                    
                cat_df = src_df[src_df['__category__'] == cat]
                if len(cat_df) > 0:
                    for col in numeric_cols[:5]:  # Limita a 5 métricas para não sobrecarregar
                        if col in cat_df.columns:
                            # Se temos períodos, precisamos alinhar os índices
                            if is_period_data:
                                # Alinha os dados da categoria com os períodos
                                if time_col in cat_df.columns:
                                    try:
                                        if pd.api.types.is_numeric_dtype(cat_df[time_col]):
                                            cat_time = pd.to_datetime(cat_df[time_col], unit='s')
                                        else:
                                            cat_time = pd.to_datetime(cat_df[time_col])
                                            
                                        cat_periods, _ = convert_timestamps_to_periods(cat_time)
                                        ax.plot(cat_periods, cat_df[col], 
                                              label=f"{cat}:{col}", alpha=0.7)
                                    except:
                                        ax.plot(range(len(cat_df)), cat_df[col],
                                              label=f"{cat}:{col}", alpha=0.7)
                                else:
                                    ax.plot(range(len(cat_df)), cat_df[col],
                                          label=f"{cat}:{col}", alpha=0.7)
                            else:
                                ax.plot(x_data[:len(cat_df)], cat_df[col], 
                                      label=f"{cat}:{col}", alpha=0.7)
            
            # Configura os ticks do eixo X para valores inteiros
            ax.xaxis.set_major_locator(ticker.MaxNLocator(integer=True))
            
            # Se for dados de período, adiciona uma anotação sobre o intervalo
            if is_period_data and len(period_time_map) >= 2:
                # Calcula e formata o intervalo médio entre períodos
                timestamps = list(period_time_map.values())
                if len(timestamps) >= 2:
                    total_seconds = (timestamps[-1] - timestamps[0]).total_seconds()
                    avg_interval = total_seconds / (len(timestamps) - 1)
                    
                    # Formata o intervalo de forma amigável
                    if avg_interval < 1:
                        interval_text = f"{avg_interval*1000:.1f} ms"
                    elif avg_interval < 60:
                        interval_text = f"{avg_interval:.1f} segundos"
                    elif avg_interval < 3600:
                        interval_text = f"{avg_interval/60:.1f} minutos"
                    else:
                        interval_text = f"{avg_interval/3600:.1f} horas"
                        
                    plt.figtext(0.5, 0.01, f"Intervalo médio entre períodos: {interval_text}", 
                              ha="center", fontsize=9, style='italic')
            
            plt.title(f"Série Temporal - {src} ({phase})")
            plt.xlabel(x_label)
            plt.ylabel("Valor")
            plt.legend(loc='best', fontsize=8)
            plt.grid(True)
            sns.set_palette("colorblind")
            plt.tight_layout()
            plt.savefig(f"{plots_dir}/serie_temporal_{clean_src}.png", dpi=120)
            plt.close(fig)

        # Análise por categoria
        for cat in categories:
            if cat == '':
                continue
                
            cat_src_df = src_df[src_df['__category__'] == cat]
            if len(cat_src_df) == 0:
                continue
                
            clean_cat = cat.replace(" ", "_").replace("/", "_")
                
            # Subplot para cada métrica numérica importante
            n_cols = min(2, len(numeric_cols))
            n_rows = int(np.ceil(len(numeric_cols) / n_cols))
            
            if n_rows > 0 and n_cols > 0:
                fig, axs = plt.subplots(n_rows, n_cols, figsize=(12, n_rows * 4))
                axs = axs.flatten() if hasattr(axs, 'flatten') else [axs]
                
                # Se tiver coluna de tempo, converte para períodos numerados
                if time_col and time_col in cat_src_df.columns:
                    try:
                        # Converte para datetime se necessário
                        if pd.api.types.is_numeric_dtype(cat_src_df[time_col]):
                            time_data = pd.to_datetime(cat_src_df[time_col], unit='s')
                        else:
                            time_data = pd.to_datetime(cat_src_df[time_col])
                        
                        # Converte timestamps para períodos numerados
                        period_data, period_map = convert_timestamps_to_periods(time_data)
                        
                        x_data = period_data
                        x_label = "Período de coleta"
                        is_period_data = True
                    except:
                        x_data = range(len(cat_src_df))
                        x_label = "Índice (ordem sequencial de coleta)"
                        is_period_data = False
                else:
                    x_data = range(len(cat_src_df))
                    x_label = "Índice (ordem sequencial de coleta)"
                    is_period_data = False
                
                for i, col in enumerate(numeric_cols):
                    if i >= len(axs) or col not in cat_src_df.columns:
                        continue
                        
                    ax = axs[i]
                    
                    # Gráfico de linha com períodos numerados
                    ax.plot(x_data, cat_src_df[col], marker='o', alpha=0.7, 
                          linewidth=1, markersize=3)
                    
                    # Configura os ticks do eixo X para valores inteiros
                    ax.xaxis.set_major_locator(ticker.MaxNLocator(integer=True))
                        
                    ax.set_xlabel(x_label)
                    ax.set_ylabel(col)
                    ax.set_title(f"{col} - {src}")
                    ax.grid(True, alpha=0.3)
                
                # Oculta subplots vazios
                for i in range(len(numeric_cols), len(axs)):
                    axs[i].axis('off')
                
                # Adiciona anotação sobre o intervalo médio se tivermos dados de período
                if is_period_data and len(period_map) >= 2:
                    timestamps = list(period_map.values())
                    if len(timestamps) >= 2:
                        total_seconds = (timestamps[-1] - timestamps[0]).total_seconds()
                        avg_interval = total_seconds / (len(timestamps) - 1)
                        
                        # Formata o intervalo de forma amigável
                        if avg_interval < 1:
                            interval_text = f"{avg_interval*1000:.1f} ms"
                        elif avg_interval < 60:
                            interval_text = f"{avg_interval:.1f} segundos"
                        elif avg_interval < 3600:
                            interval_text = f"{avg_interval/60:.1f} minutos"
                        else:
                            interval_text = f"{avg_interval/3600:.1f} horas"
                            
                        plt.figtext(0.5, 0.01, f"Intervalo médio entre períodos: {interval_text}", 
                                  ha="center", fontsize=9, style='italic')
                
                plt.tight_layout()
                plt.savefig(f"{plots_dir}/metricas_{clean_src}_{clean_cat}.png", dpi=120)
                plt.close(fig)
                
                # Distribuição de valores para métricas chave
                plt.figure(figsize=(12, n_rows * 3))
                
                for i, col in enumerate(numeric_cols):
                    if col not in cat_src_df.columns:
                        continue
                        
                    plt.subplot(n_rows, n_cols, i + 1)
                    sns.histplot(cat_src_df[col].dropna(), kde=True, color="#377eb8")
                    plt.title(f"Distribuição - {col}")
                    plt.xlabel(col)
                
                plt.suptitle(f"Distribuições - {src} ({cat})")
                plt.tight_layout()
                plt.savefig(f"{plots_dir}/dist_{clean_src}_{clean_cat}.png", dpi=120)
                plt.close()

    # Matriz de correlação para todas as métricas
    corr_cols = [col for col in numeric_cols if col in df.columns]
    if len(corr_cols) > 1 and len(df) > 1:
        plt.figure(figsize=(10, 8))
        corr = df[corr_cols].corr()
        mask = np.triu(np.ones_like(corr, dtype=bool))
        sns.heatmap(corr, mask=mask, annot=True, fmt=".2f", cmap="coolwarm", 
                  square=True, linewidths=0.5)
        plt.title(f"Matriz de Correlação ({phase})")
        plt.tight_layout()
        plt.savefig(f"{plots_dir}/correlacao_geral.png", dpi=120)
        plt.close()


def plot_tenant_comparison(all_data, metrics_to_compare=None, max_metrics=10):
    """
    Cria gráficos comparativos entre tenants para as mesmas métricas.
    
    Args:
        all_data: Dicionário onde as chaves são as fases e os valores são DataFrames com os dados
        metrics_to_compare: Lista de métricas específicas para comparar. Se None, serão escolhidas
                          as métricas mais comuns entre os tenants.
        max_metrics: Número máximo de métricas para comparar se metrics_to_compare não for especificado
    """
    print(f"\nGerando gráficos comparativos entre tenants...")
    
    # Cria diretório para os gráficos comparativos
    plots_dir = os.path.join("plots", "comparacao_tenants")
    os.makedirs(plots_dir, exist_ok=True)
    
    # Para cada fase, criar gráficos comparando os tenants
    for phase, df in all_data.items():
        # Obtém as categorias que são tenants (tenant-a, tenant-b, tenant-c, tenant-d)
        tenant_categories = [cat for cat in df['__category__'].unique() 
                          if cat.startswith('tenant-')]
        
        if len(tenant_categories) <= 1:
            print(f"  Fase {phase}: Insuficientes tenants para comparação ({len(tenant_categories)} encontrados)")
            continue
            
        print(f"  Fase {phase}: Comparando {len(tenant_categories)} tenants: {', '.join(tenant_categories)}")
        
        # Encontrar métricas comuns entre todos os tenants
        common_metrics = None
        tenant_sources = {}
        
        # Procura coluna de timestamp
        time_col = find_timestamp_column(df)
        print(f"  Coluna de timestamp identificada: {time_col if time_col else 'Nenhuma'}")
        
        # Converte timestamps para períodos numerados se disponíveis
        period_data = None
        period_map = {}
        is_period_data = False
        
        if time_col and time_col in df.columns:
            try:
                # Converte para datetime se necessário
                if pd.api.types.is_numeric_dtype(df[time_col]):
                    time_data = pd.to_datetime(df[time_col], unit='s')
                else:
                    time_data = pd.to_datetime(df[time_col])
                
                # Converte timestamps para períodos numerados
                period_data, period_map = convert_timestamps_to_periods(time_data)
                is_period_data = True
                x_label = "Período de coleta"
            except Exception as e:
                print(f"  Erro ao converter timestamps para períodos: {str(e)}")
                is_period_data = False
                x_label = "Índice (ordem sequencial de coleta)"
        else:
            is_period_data = False
            x_label = "Índice (ordem sequencial de coleta)"
        
        # Coleta todas as fontes e métricas por tenant
        for tenant in tenant_categories:
            tenant_df = df[df['__category__'] == tenant]
            tenant_sources[tenant] = tenant_df['__source__'].unique()
            
            # Obtém todas as métricas numéricas para este tenant
            numeric_cols = tenant_df.select_dtypes(include=[np.number]).columns.tolist()
            # Exclui colunas de metadados
            tenant_metrics = set([col for col in numeric_cols 
                              if col not in ['__source__', '__category__', '__path__']])
            
            # Atualiza o conjunto de métricas comuns
            if common_metrics is None:
                common_metrics = tenant_metrics
            else:
                common_metrics = common_metrics.intersection(tenant_metrics)
        
        # Se não houver métricas comuns, pular
        if not common_metrics or len(common_metrics) == 0:
            print(f"    Nenhuma métrica comum encontrada entre os tenants")
            continue
            
        # Se houver muitas métricas comuns e não foram especificadas quais comparar,
        # escolher as mais relevantes
        if metrics_to_compare is None:
            if len(common_metrics) > max_metrics:
                # Seleciona um subconjunto de métricas mais interessantes
                common_metrics = sorted(list(common_metrics))[:max_metrics]
                print(f"    Comparando {max_metrics} métricas mais comuns (de {len(common_metrics)} disponíveis)")
            else:
                common_metrics = sorted(list(common_metrics))
                print(f"    Comparando {len(common_metrics)} métricas comuns")
        else:
            # Usa as métricas específicas solicitadas que existem nos dados
            common_metrics = [m for m in metrics_to_compare if m in common_metrics]
            if not common_metrics:
                print(f"    Nenhuma das métricas solicitadas está disponível entre os tenants")
                continue
            print(f"    Comparando {len(common_metrics)} métricas solicitadas")
        
        # Encontrar fontes comuns entre tenants para cada métrica
        for metric in common_metrics:
            print(f"    Comparando métrica: {metric}")
            
            # Para cada métrica, encontrar as fontes que a contêm em cada tenant
            metric_sources = {}
            for tenant in tenant_categories:
                tenant_df = df[df['__category__'] == tenant]
                # Encontrar fontes que contêm esta métrica
                valid_sources = []
                for source in tenant_sources[tenant]:
                    src_df = tenant_df[tenant_df['__source__'] == source]
                    if metric in src_df.columns:
                        valid_sources.append(source)
                if valid_sources:
                    metric_sources[tenant] = valid_sources
            
            # Se não houver fontes suficientes para esta métrica, pular
            if len(metric_sources) < 2:
                print(f"      Insuficientes fontes para a métrica {metric}")
                continue
            
            # Cria um gráfico para esta métrica comparando os tenants
            fig, ax = plt.subplots(figsize=(14, 7))
            
            # Para cada tenant, plota a métrica para cada fonte válida
            for tenant in metric_sources:
                for source in metric_sources[tenant]:
                    tenant_src_df = df[(df['__category__'] == tenant) & 
                                    (df['__source__'] == source)]
                    
                    if metric in tenant_src_df.columns and len(tenant_src_df[metric]) > 0:
                        # Se houver dados de período, usar eles para o eixo x
                        if is_period_data and time_col in tenant_src_df.columns:
                            try:
                                # Converter para períodos específicos deste tenant/source
                                if pd.api.types.is_numeric_dtype(tenant_src_df[time_col]):
                                    tenant_time = pd.to_datetime(tenant_src_df[time_col], unit='s')
                                else:
                                    tenant_time = pd.to_datetime(tenant_src_df[time_col])
                                    
                                tenant_periods, _ = convert_timestamps_to_periods(tenant_time)
                                ax.plot(tenant_periods, tenant_src_df[metric],
                                       label=f"{tenant} ({source})", alpha=0.8, marker='o', 
                                       markersize=3, linewidth=1.5)
                            except Exception as e:
                                # Fallback para índices
                                print(f"      Erro ao processar períodos para {tenant}/{source}: {str(e)}")
                                ax.plot(range(len(tenant_src_df)), tenant_src_df[metric], 
                                       label=f"{tenant} ({source})", alpha=0.8, marker='o', 
                                       markersize=3, linewidth=1.5)
                        else:
                            # Caso contrário, usar índice
                            ax.plot(range(len(tenant_src_df)), tenant_src_df[metric], 
                                   label=f"{tenant} ({source})", alpha=0.8, marker='o', 
                                   markersize=3, linewidth=1.5)
            
            ax.set_title(f"Comparação de {metric} entre tenants ({phase})")
            ax.set_xlabel(x_label)
            ax.set_ylabel(metric)
            ax.grid(True, alpha=0.3)
            ax.legend(loc='best')
            
            # Configura os ticks do eixo X para valores inteiros
            ax.xaxis.set_major_locator(ticker.MaxNLocator(integer=True))
            
            # Adiciona anotação sobre o intervalo se tivermos dados de período
            if is_period_data and len(period_map) >= 2:
                timestamps = list(period_map.values())
                if len(timestamps) >= 2:
                    total_seconds = (timestamps[-1] - timestamps[0]).total_seconds()
                    avg_interval = total_seconds / (len(timestamps) - 1)
                    
                    # Formata o intervalo de forma amigável
                    if avg_interval < 1:
                        interval_text = f"{avg_interval*1000:.1f} ms"
                    elif avg_interval < 60:
                        interval_text = f"{avg_interval:.1f} segundos"
                    elif avg_interval < 3600:
                        interval_text = f"{avg_interval/60:.1f} minutos"
                    else:
                        interval_text = f"{avg_interval/3600:.1f} horas"
                        
                    plt.figtext(0.5, 0.01, f"Intervalo médio entre períodos: {interval_text}", 
                              ha="center", fontsize=9, style='italic')
            
            # Salva o gráfico
            clean_phase = phase.replace(" ", "_").replace("/", "_")
            clean_metric = metric.replace(" ", "_").replace("/", "_")[:30]
            plt.tight_layout()
            plt.savefig(f"{plots_dir}/comp_{clean_phase}_{clean_metric}.png", dpi=120)
            plt.close(fig)
            
            # Inclui um boxplot para visualizar a distribuição entre tenants
            plt.figure(figsize=(12, 6))
            
            boxplot_data = []
            boxplot_labels = []
            
            for tenant in metric_sources:
                for source in metric_sources[tenant]:
                    tenant_src_df = df[(df['__category__'] == tenant) & 
                                     (df['__source__'] == source)]
                    
                    if metric in tenant_src_df.columns and len(tenant_src_df[metric]) > 0:
                        boxplot_data.append(tenant_src_df[metric].dropna().tolist())
                        boxplot_labels.append(f"{tenant} ({source})")
            
            if boxplot_data:
                plt.boxplot(boxplot_data, labels=boxplot_labels)
                plt.title(f"Distribuição de {metric} entre tenants ({phase})")
                plt.ylabel(metric)
                plt.grid(True, alpha=0.3)
                plt.xticks(rotation=45, ha='right')
                plt.tight_layout()
                plt.savefig(f"{plots_dir}/boxplot_{clean_phase}_{clean_metric}.png", dpi=120)
                plt.close()
                
            # Adicionar uma nova visualização: gráfico de barras com médias
            plt.figure(figsize=(12, 6))
            
            bar_labels = []
            bar_values = []
            bar_std = []
            
            for tenant in metric_sources:
                for source in metric_sources[tenant]:
                    tenant_src_df = df[(df['__category__'] == tenant) & 
                                     (df['__source__'] == source)]
                    
                    if metric in tenant_src_df.columns and len(tenant_src_df[metric]) > 0:
                        values = tenant_src_df[metric].dropna()
                        if len(values) > 0:
                            bar_labels.append(f"{tenant} ({source})")
                            bar_values.append(values.mean())
                            bar_std.append(values.std())
            
            if bar_values:
                y_pos = np.arange(len(bar_labels))
                plt.bar(y_pos, bar_values, yerr=bar_std, alpha=0.7, capsize=5)
                plt.xticks(y_pos, bar_labels, rotation=45, ha='right')
                plt.title(f"Média de {metric} entre tenants ({phase})")
                plt.ylabel(f"{metric} (média ± desvio padrão)")
                plt.grid(True, alpha=0.3, axis='y')
                plt.tight_layout()
                plt.savefig(f"{plots_dir}/media_{clean_phase}_{clean_metric}.png", dpi=120)
                plt.close()