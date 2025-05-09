"""
Processador de dados das métricas do Prometheus.
"""
import logging
import pandas as pd
import numpy as np

logger = logging.getLogger(__name__)

class MetricsDataProcessor:
    """Classe para processamento de dados das métricas."""
    
    @staticmethod
    def extract_values(metric_data):
        """
        Extrai valores de uma resposta do Prometheus.
        
        Args:
            metric_data (dict): Resposta do Prometheus
            
        Returns:
            list: Lista de dicionários com os dados extraídos
        """
        if not metric_data or 'data' not in metric_data or 'result' not in metric_data['data']:
            logger.warning("Dados de métrica inválidos ou vazios")
            return []
            
        results = []
        
        for item in metric_data['data']['result']:
            metric_info = item['metric']
            
            # Para consultas instantâneas
            if 'value' in item:
                timestamp, value = item['value']
                results.append({
                    'timestamp': timestamp,
                    'value': float(value),
                    **metric_info
                })
            
            # Para consultas de intervalos
            elif 'values' in item:
                for ts, val in item['values']:
                    results.append({
                        'timestamp': ts,
                        'value': float(val),
                        **metric_info
                    })
                    
        return results
    
    @staticmethod
    def to_dataframe(metrics_data):
        """
        Converte dados de métricas para um DataFrame do pandas.
        
        Args:
            metrics_data (list): Lista de dicionários com dados de métricas
            
        Returns:
            pandas.DataFrame: DataFrame com os dados
        """
        if not metrics_data:
            return pd.DataFrame()
            
        df = pd.DataFrame(metrics_data)
        
        # Converte timestamp para datetime
        if 'timestamp' in df.columns:
            df['timestamp'] = pd.to_datetime(df['timestamp'], unit='s')
            
        return df
    
    @staticmethod
    def calculate_rate(dataframe, window='5min'):
        """
        Calcula a taxa de mudança (rate) para métricas acumulativas.
        
        Args:
            dataframe (pandas.DataFrame): DataFrame com dados de séries temporais
            window (str): Janela de tempo para cálculo da taxa
            
        Returns:
            pandas.DataFrame: DataFrame com taxas calculadas
        """
        if dataframe.empty or 'timestamp' not in dataframe.columns or 'value' not in dataframe.columns:
            logger.warning("DataFrame inválido para cálculo de taxa")
            return pd.DataFrame()
        
        # Agrupa por todas as colunas de metadados, se existirem
        metadata_cols = [col for col in dataframe.columns if col not in ['timestamp', 'value']]
        
        if metadata_cols:
            # Define o timestamp como índice para operações de séries temporais
            df = dataframe.set_index('timestamp')
            
            # Agrupa por colunas de metadados e calcula a taxa para cada grupo
            grouped = df.groupby(metadata_cols)
            rates = grouped['value'].diff() / grouped['value'].index.to_series().diff().dt.total_seconds()
            
            # Reset índice
            result = pd.DataFrame({
                'rate': rates
            }).reset_index()
            
            return result
        else:
            # Caso simples sem metadados
            df = dataframe.set_index('timestamp')
            rates = df['value'].diff() / df.index.to_series().diff().dt.total_seconds()
            
            return pd.DataFrame({
                'timestamp': df.index,
                'rate': rates
            }).reset_index(drop=True)
    
    @staticmethod
    def resample_metrics(dataframe, rule='1min', agg='mean'):
        """
        Reamostra os dados para a frequência especificada.
        
        Args:
            dataframe (pandas.DataFrame): DataFrame com dados de séries temporais
            rule (str): Regra de reamostragem (ex: '1min', '5min', '1h')
            agg (str): Função de agregação ('mean', 'sum', 'max', etc)
            
        Returns:
            pandas.DataFrame: DataFrame com dados reamostrados
        """
        if dataframe.empty or 'timestamp' not in dataframe.columns:
            logger.warning("DataFrame inválido para reamostragem")
            return pd.DataFrame()
            
        # Define timestamp como índice
        df = dataframe.set_index('timestamp')
        
        # Colunas de metadados, se existirem
        metadata_cols = [col for col in df.columns if col != 'value']
        
        if metadata_cols:
            # Agrupa por colunas de metadados
            result = df.groupby(metadata_cols).resample(rule)['value'].agg(agg).reset_index()
        else:
            # Caso simples sem metadados
            result = df.resample(rule)['value'].agg(agg).reset_index()
            
        return result
