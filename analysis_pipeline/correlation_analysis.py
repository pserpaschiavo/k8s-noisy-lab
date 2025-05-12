### analysis_pipeline/correlation_analysis.py

import pandas as pd
import numpy as np
import seaborn as sns
import matplotlib.pyplot as plt
from scipy.stats import spearmanr, pearsonr


def compute_correlations(df, phase):
    print(f"\nMatriz de correlação para a fase: {phase}")

    numeric_df = df.select_dtypes(include=[np.number])
    corr_matrix = numeric_df.corr(method='pearson')
    print(corr_matrix.round(2))

    # Heatmap
    plt.figure(figsize=(12, 8))
    sns.set_palette("colorblind")
    sns.heatmap(corr_matrix, annot=True, cmap='cividis', fmt=".2f", square=True)
    plt.title(f"Correlação (Pearson) - {phase}")
    plt.tight_layout()
    plt.savefig(f"correlation_heatmap_{phase}.png")
    plt.close()

    # Correlação de Spearman (não-paramétrica)
    print(f"\nCorrelação de Spearman entre métricas:")
    for i, col1 in enumerate(numeric_df.columns):
        for j, col2 in enumerate(numeric_df.columns):
            if i < j:
                coef, p = spearmanr(numeric_df[col1], numeric_df[col2])
                if abs(coef) > 0.6:
                    print(f"{col1:25} x {col2:25} => Spearman: {coef:.2f} (p={p:.4f})")
