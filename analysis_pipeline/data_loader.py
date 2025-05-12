### analysis_pipeline/data_loader.py

import pandas as pd
import os

def load_metrics(path):
    """
    Carrega recursivamente todos os arquivos CSV de métricas no diretório fornecido
    e seus subdiretórios, concatenando em um único DataFrame com metadados de origem.
    """
    all_dfs = []
    
    # Percorre recursivamente todos os subdiretórios
    for root, dirs, files in os.walk(path):
        # Extrai a categoria baseada no subdiretório (ex: "accepted", "tenant-a", etc)
        category = os.path.basename(root)
        
        # Pula o diretório raiz para categorização
        if root == path:
            category = ""
        
        # Processa todos os arquivos CSV no diretório atual
        for filename in files:
            if filename.endswith(".csv"):
                full_path = os.path.join(root, filename)
                
                try:
                    df = pd.read_csv(full_path)
                    
                    # Adiciona metadados úteis
                    df['__source__'] = filename.replace(".csv", "")
                    df['__category__'] = category
                    df['__path__'] = os.path.relpath(full_path, path)
                    
                    all_dfs.append(df)
                    print(f"Carregado: {os.path.relpath(full_path, path)}")
                except Exception as e:
                    print(f"Erro ao carregar {full_path}: {e}")

    if not all_dfs:
        raise FileNotFoundError(f"Nenhum CSV encontrado em: {path}")

    print(f"Total de arquivos CSV carregados: {len(all_dfs)}")
    combined = pd.concat(all_dfs, ignore_index=True)
    return combined