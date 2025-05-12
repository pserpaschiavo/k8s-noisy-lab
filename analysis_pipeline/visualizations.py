### analysis_pipeline/visualizations.py

import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import os


def plot_all(df, phase):
    print(f"\nGerando gráficos para a fase: {phase}")

    os.makedirs("plots", exist_ok=True)

    numeric_cols = df.select_dtypes(include=['number']).columns
    sources = df['__source__'].unique()

    for src in sources:
        sub_df = df[df['__source__'] == src]

        # Série temporal
        plt.figure(figsize=(12, 4))
        for col in numeric_cols:
            plt.plot(sub_df.index, sub_df[col], label=col)
        plt.title(f"Série Temporal - {src} ({phase})")
        plt.xlabel("Índice")
        plt.ylabel("Valor")
        plt.legend()
        plt.grid(True)
        sns.set_palette("colorblind")
        plt.tight_layout()
        plt.savefig(f"plots/serie_temporal_{src}_{phase}.png")
        plt.close()

        # Distribuições
        for col in numeric_cols:
            plt.figure(figsize=(6, 4))
            sns.histplot(sub_df[col].dropna(), kde=True, color="#377eb8")
            plt.title(f"Distribuição - {src} / {col} ({phase})")
            plt.xlabel(col)
            plt.tight_layout()
            plt.savefig(f"plots/dist_{src}_{col}_{phase}.png")
            plt.close()