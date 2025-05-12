### analysis_pipeline/correlation_analysis.py

import pandas as pd
import numpy as np
import seaborn as sns
import matplotlib.pyplot as plt
import os
from scipy.stats import spearmanr, pearsonr


def compute_correlations(df, phase):
    print(f"\nAnálise de correlação para a fase: {phase}")
    
    # Cria diretório para salvar os gráficos de correlação
    plots_dir = os.path.join("plots", phase.replace(" ", "_").replace("/", "_"))
    os.makedirs(plots_dir, exist_ok=True)

    # Seleciona apenas colunas numéricas
    numeric_df = df.select_dtypes(include=[np.number])
    
    # Ignora colunas de metadados
    exclude_cols = ['__source__', '__category__', '__path__']
    for col in exclude_cols:
        if col in numeric_df.columns:
            numeric_df = numeric_df.drop(col, axis=1)
            
    # Verifica se há colunas numéricas suficientes para análise
    if len(numeric_df.columns) < 2:
        print("  Insuficientes colunas numéricas para análise de correlação.")
        return
        
    # Matriz de correlação de Pearson
    corr_matrix = numeric_df.corr(method='pearson')
    print("\nMatriz de correlação (Pearson):")
    print(corr_matrix.round(2))

    # Heatmap de correlação
    if len(corr_matrix) > 1:
        plt.figure(figsize=(10, 8))
        mask = np.triu(np.ones_like(corr_matrix, dtype=bool))
        sns.set_palette("colorblind")
        sns.heatmap(corr_matrix, mask=mask, annot=True, cmap='cividis', 
                  fmt=".2f", square=True, linewidths=0.5)
        plt.title(f"Correlação (Pearson) - {phase}")
        plt.tight_layout()
        plt.savefig(f"{plots_dir}/correlacao_pearson.png", dpi=120)
        plt.close()

    # Correlações importantes (Pearson e Spearman)
    print("\nCorrelações significativas entre métricas:")
    for i, col1 in enumerate(numeric_df.columns):
        for j, col2 in enumerate(numeric_df.columns):
            if i < j:  # Evita duplicações e autocorrelações
                # Apenas se tiver dados suficientes
                if len(numeric_df[col1].dropna()) > 3 and len(numeric_df[col2].dropna()) > 3:
                    try:
                        # Correlação de Pearson
                        p_coef, p_val = pearsonr(numeric_df[col1].dropna(), numeric_df[col2].dropna())
                        
                        # Correlação de Spearman (não-paramétrica)
                        s_coef, s_val = spearmanr(numeric_df[col1].dropna(), numeric_df[col2].dropna())
                        
                        # Reporta apenas correlações significativas
                        if abs(p_coef) > 0.6 or abs(s_coef) > 0.6:
                            print(f"  {col1:25} x {col2:25}")
                            print(f"    Pearson: {p_coef:.2f} (p={p_val:.4f})")
                            print(f"    Spearman: {s_coef:.2f} (p={s_val:.4f})")
                            
                            # Gera scatter plot para correlações importantes
                            if abs(p_coef) > 0.7 or abs(s_coef) > 0.7:
                                plt.figure(figsize=(8, 6))
                                sns.scatterplot(x=numeric_df[col1], y=numeric_df[col2], alpha=0.7)
                                plt.xlabel(col1)
                                plt.ylabel(col2)
                                plt.title(f"Correlação: {col1} vs {col2}\nPearson={p_coef:.2f}, Spearman={s_coef:.2f}")
                                plt.grid(True, alpha=0.3)
                                plt.tight_layout()
                                # Limita o tamanho do nome do arquivo
                                clean_col1 = col1[:20].replace(" ", "_")
                                clean_col2 = col2[:20].replace(" ", "_")
                                plt.savefig(f"{plots_dir}/scatter_{clean_col1}_vs_{clean_col2}.png", dpi=100)
                                plt.close()
                    except Exception as e:
                        print(f"  Erro ao calcular correlação entre {col1} e {col2}: {str(e)}")
    
    # Análise por categoria se tivermos essa informação
    if '__category__' in df.columns:
        categories = df['__category__'].unique()
        
        # Verifica correlações entre categorias
        if len(categories) > 1:
            print("\nAnálise de correlação entre diferentes categorias:")
            
            for cat1 in categories:
                if cat1 == '':
                    continue
                    
                for cat2 in categories:
                    if cat2 == '' or cat1 >= cat2:  # Evita repetições
                        continue
                        
                    cat1_df = df[df['__category__'] == cat1].select_dtypes(include=[np.number])
                    cat2_df = df[df['__category__'] == cat2].select_dtypes(include=[np.number])
                    
                    # Remove colunas de metadados
                    for col in exclude_cols:
                        if col in cat1_df.columns: cat1_df = cat1_df.drop(col, axis=1)
                        if col in cat2_df.columns: cat2_df = cat2_df.drop(col, axis=1)
                    
                    print(f"\n  Correlações entre {cat1} e {cat2}:")
                    
                    # Encontra colunas em comum
                    common_cols = set(cat1_df.columns).intersection(set(cat2_df.columns))
                    
                    if len(common_cols) > 0:
                        for col in common_cols:
                            # Verifica se temos dados suficientes
                            if (len(cat1_df) > 3 and len(cat2_df) > 3 and 
                                len(cat1_df[col].dropna()) > 3 and len(cat2_df[col].dropna()) > 3):
                                try:
                                    # Calcula correlação para a mesma métrica entre categorias diferentes
                                    p_coef, p_val = pearsonr(cat1_df[col].dropna(), cat2_df[col].dropna())
                                    s_coef, s_val = spearmanr(cat1_df[col].dropna(), cat2_df[col].dropna())
                                    
                                    print(f"    Métrica {col}:")
                                    print(f"      Pearson: {p_coef:.2f} (p={p_val:.4f})")
                                    print(f"      Spearman: {s_coef:.2f} (p={s_val:.4f})")
                                except Exception as e:
                                    print(f"    Erro ao calcular correlação para {col}: {str(e)}")
                    else:
                        print("    Nenhuma coluna em comum para análise.")
