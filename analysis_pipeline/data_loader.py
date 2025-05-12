### analysis_pipeline/data_loader.py

import pandas as pd
import os

def load_metrics(path):
    """
    Carrega todos os arquivos CSV de métricas no diretório fornecido
    e concatena em um único DataFrame com um prefixo de origem.
    """
    all_dfs = []
    for filename in os.listdir(path):
        if filename.endswith(".csv"):
            full_path = os.path.join(path, filename)
            df = pd.read_csv(full_path)
            df['__source__'] = filename.replace(".csv", "")
            all_dfs.append(df)

    if not all_dfs:
        raise FileNotFoundError(f"Nenhum CSV encontrado em: {path}")

    combined = pd.concat(all_dfs, ignore_index=True)
    return combined