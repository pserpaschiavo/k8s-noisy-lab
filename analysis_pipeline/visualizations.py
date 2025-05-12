### analysis_pipeline/visualizations.py

import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import os
import numpy as np


def plot_all(df, phase):
    print(f"\nGerando gráficos para a fase: {phase}")

    # Cria diretório para salvar os gráficos, organizados por fase
    plots_dir = os.path.join("plots", phase.replace(" ", "_").replace("/", "_"))
    os.makedirs(plots_dir, exist_ok=True)

    numeric_cols = df.select_dtypes(include=['number']).columns.tolist()
    
    # Remove colunas de timestamp se existirem e as usa para o eixo x
    time_cols = [col for col in numeric_cols if 'time' in col.lower() or 'timestamp' in col.lower()]
    if time_cols:
        time_col = time_cols[0]
        numeric_cols = [col for col in numeric_cols if col != time_col]
    else:
        time_col = None

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
            
            # Se tiver coluna de tempo, usa ela para o eixo x
            if time_col:
                x_data = src_df[time_col]
                x_label = time_col
            else:
                x_data = range(len(src_df))
                x_label = "Índice"
            
            # Para cada categoria, plotar como uma linha diferente
            for cat in categories:
                if cat == '':
                    continue
                    
                cat_df = src_df[src_df['__category__'] == cat]
                if len(cat_df) > 0:
                    for col in numeric_cols[:5]:  # Limita a 5 métricas para não sobrecarregar
                        if col in cat_df.columns:
                            plt.plot(x_data[:len(cat_df)], cat_df[col], 
                                    label=f"{cat}:{col}", alpha=0.7)
            
            plt.title(f"Série Temporal - {src} ({phase})")
            plt.xlabel(x_label)
            plt.ylabel("Valor")
            plt.legend(loc='best', fontsize=8)
            plt.grid(True)
            sns.set_palette("colorblind")
            plt.tight_layout()
            plt.savefig(f"{plots_dir}/serie_temporal_{clean_src}.png", dpi=120)
            plt.close()

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
                plt.figure(figsize=(12, n_rows * 4))
                
                for i, col in enumerate(numeric_cols):
                    if col not in cat_src_df.columns:
                        continue
                        
                    plt.subplot(n_rows, n_cols, i + 1)
                    
                    # Gráfico de linha
                    if time_col:
                        plt.plot(cat_src_df[time_col], cat_src_df[col], marker='o', 
                               alpha=0.7, linewidth=1, markersize=3)
                        plt.xlabel(time_col)
                    else:
                        plt.plot(cat_src_df[col], marker='o', alpha=0.7, 
                               linewidth=1, markersize=3)
                        plt.xlabel("Índice")
                        
                    plt.ylabel(col)
                    plt.title(f"{col} - {src}")
                    plt.grid(True, alpha=0.3)
                
                plt.tight_layout()
                plt.savefig(f"{plots_dir}/metricas_{clean_src}_{clean_cat}.png", dpi=120)
                plt.close()
                
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