"""
Coletor principal de métricas do Prometheus.
"""
import time
import logging
from datetime import datetime, timedelta
import requests
from urllib.parse import urljoin

from prometheus_metrics.config import PROMETHEUS_URL, REQUEST_TIMEOUT

logger = logging.getLogger(__name__)

class PrometheusCollector:
    """Classe para coletar métricas do Prometheus."""
    
    def __init__(self, prometheus_url=None):
        """
        Inicializa o coletor.
        
        Args:
            prometheus_url (str): URL do servidor Prometheus
        """
        self.prometheus_url = prometheus_url or PROMETHEUS_URL
        self.api_url = urljoin(self.prometheus_url, '/api/v1/')
    
    def query(self, metric_query):
        """
        Executa uma consulta instantânea ao Prometheus.
        
        Args:
            metric_query (str): Consulta PromQL
            
        Returns:
            dict: Resposta do Prometheus
        """
        query_url = urljoin(self.api_url, 'query')
        try:
            response = requests.get(
                query_url,
                params={'query': metric_query},
                timeout=REQUEST_TIMEOUT
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Erro ao consultar Prometheus: {e}")
            return None
            
    def query_range(self, metric_query, start_time, end_time=None, step='15s'):
        """
        Executa uma consulta de intervalo ao Prometheus.
        
        Args:
            metric_query (str): Consulta PromQL
            start_time (datetime): Horário de início
            end_time (datetime): Horário de término (padrão: agora)
            step (str): Intervalo entre pontos de dados
            
        Returns:
            dict: Resposta do Prometheus
        """
        end_time = end_time or datetime.now()
        query_url = urljoin(self.api_url, 'query_range')
        
        params = {
            'query': metric_query,
            'start': start_time.timestamp(),
            'end': end_time.timestamp(),
            'step': step
        }
        
        try:
            response = requests.get(
                query_url,
                params=params,
                timeout=REQUEST_TIMEOUT
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Erro ao consultar intervalo no Prometheus: {e}")
            return None
    
    def get_metric_last_value(self, metric_name):
        """
        Obtém o valor mais recente de uma métrica.
        
        Args:
            metric_name (str): Nome da métrica
            
        Returns:
            dict: Valor mais recente da métrica
        """
        return self.query(metric_name)
    
    def get_metric_over_time(self, metric_name, hours=1, step='15s'):
        """
        Obtém os valores de uma métrica ao longo do tempo.
        
        Args:
            metric_name (str): Nome da métrica
            hours (int): Número de horas para olhar para trás
            step (str): Intervalo entre pontos de dados
            
        Returns:
            dict: Valores da métrica ao longo do tempo
        """
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=hours)
        
        return self.query_range(metric_name, start_time, end_time, step)
