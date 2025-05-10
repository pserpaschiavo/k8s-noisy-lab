"""
Exportador de dados para JSON.
"""
import os
import json
import logging
from datetime import datetime

from metrics.config import OUTPUT_DIR

logger = logging.getLogger(__name__)

class JSONExporter:
    """Classe para exportação de dados para JSON."""
    
    def __init__(self, output_dir=None):
        """
        Inicializa o exportador JSON.
        
        Args:
            output_dir (str): Diretório de saída para os arquivos JSON
        """
        self.output_dir = output_dir or OUTPUT_DIR
        os.makedirs(self.output_dir, exist_ok=True)
    
    def export_data(self, data, filename=None, prefix='metrics'):
        """
        Exporta dados para um arquivo JSON.
        
        Args:
            data: Dados para exportar (devem ser serializáveis em JSON)
            filename (str): Nome do arquivo (opcional)
            prefix (str): Prefixo para o nome do arquivo
            
        Returns:
            str: Caminho do arquivo JSON gerado
        """
        if not data:
            logger.warning("Dados vazios, nada para exportar")
            return None
            
        # Gera um nome de arquivo baseado no timestamp atual se não for fornecido
        if not filename:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            filename = f"{prefix}_{timestamp}.json"
            
        file_path = os.path.join(self.output_dir, filename)
        
        # Define uma classe personalizada para serializar dados que não são JSON nativos
        class CustomJSONEncoder(json.JSONEncoder):
            def default(self, obj):
                if hasattr(obj, 'to_json'):
                    return obj.to_json()
                if hasattr(obj, '__dict__'):
                    return obj.__dict__
                try:
                    return str(obj)
                except:
                    return None
        
        # Exporta para JSON
        with open(file_path, 'w') as json_file:
            json.dump(data, json_file, cls=CustomJSONEncoder, indent=2)
            
        logger.info(f"Dados exportados para {file_path}")
        
        return file_path
    
    def export_dataframe(self, df, filename=None, prefix='metrics', orient='records'):
        """
        Exporta um DataFrame para um arquivo JSON.
        
        Args:
            df (pandas.DataFrame): DataFrame para exportar
            filename (str): Nome do arquivo (opcional)
            prefix (str): Prefixo para o nome do arquivo
            orient (str): Orientação do formato JSON ('records', 'split', 'index', etc)
            
        Returns:
            str: Caminho do arquivo JSON gerado
        """
        if df is None or df.empty:
            logger.warning("DataFrame vazio, nada para exportar")
            return None
        
        # Converte DataFrame para formato de dicionário
        data = json.loads(df.to_json(orient=orient))
        
        return self.export_data(data, filename, prefix)
