## analysis_pipeline/stats_summary.py

import pandas as pd
import numpy as np
from scipy import stats
from statsmodels.tsa.stattools import adfuller


def summarize_metrics(df, phase):
    print(f"\nResumo estatístico para a fase: {phase}")

    # Remove colunas não numéricas exceto __source__
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    summary = df[numeric_cols].describe(percentiles=[.25, .5, .75])
    print(summary)

    print("\nSkewness e Kurtosis:")
    for col in numeric_cols:
        skew = stats.skew(df[col].dropna())
        kurt = stats.kurtosis(df[col].dropna())
        print(f"{col:30} Skew: {skew:.2f}, Kurtosis: {kurt:.2f}")

    print("\nTeste de estacionariedade (ADF):")
    for col in numeric_cols:
        try:
            result = adfuller(df[col].dropna())
            print(f"{col:30} ADF p-value: {result[1]:.4f}")
        except Exception as e:
            print(f"{col:30} Erro no ADF: {str(e)}")

