"""
Exportador de dados para CSV.
"""
import os
import logging
from datetime import datetime
import pandas as pd

from metrics.config import OUTPUT_DIR

logger = logging.getLogger(__name__)

class CSVExporter:
    """Classe para exportação de dados para CSV."""
    
    def __init__(self, output_dir=None):
        """
        Inicializa o exportador CSV.
        
        Args:
            output_dir (str): Diretório de saída para os arquivos CSV
        """
        self.output_dir = output_dir or OUTPUT_DIR
        os.makedirs(self.output_dir, exist_ok=True)
    
    def export_dataframe(self, df, filename=None, prefix='metrics'):
        """
        Exporta um DataFrame para um arquivo CSV.
        
        Args:
            df (pandas.DataFrame): DataFrame para exportar
            filename (str): Nome do arquivo (opcional)
            prefix (str): Prefixo para o nome do arquivo
            
        Returns:
            str: Caminho do arquivo CSV gerado
        """
        if df is None or df.empty:
            logger.warning("DataFrame vazio, nada para exportar")
            return None
            
        # Gera um nome de arquivo baseado no timestamp atual se não for fornecido
        if not filename:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            filename = f"{prefix}_{timestamp}.csv"
            
        file_path = os.path.join(self.output_dir, filename)
        
        # Exporta para CSV
        df.to_csv(file_path, index=False)
        logger.info(f"Dados exportados para {file_path}")
        
        return file_path
    
    def export_dict_data(self, data, filename=None, prefix='metrics'):
        """
        Exporta dados em formato de dicionário para um arquivo CSV.
        
        Args:
            data (dict ou list): Dados para exportar
            filename (str): Nome do arquivo (opcional)
            prefix (str): Prefixo para o nome do arquivo
            
        Returns:
            str: Caminho do arquivo CSV gerado
        """
        if not data:
            logger.warning("Dados vazios, nada para exportar")
            return None
            
        # Converte para DataFrame
        df = pd.DataFrame(data) if isinstance(data, list) else pd.DataFrame([data])
        
        return self.export_dataframe(df, filename, prefix)
