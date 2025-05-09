"""
Coletor de métricas HTTP.
"""
import logging
from prometheus_metrics.collector import PrometheusCollector
from prometheus_metrics.config import BASIC_METRICS, CALCULATED_METRICS

logger = logging.getLogger(__name__)

class HttpMetricsCollector:
    """Classe para coletar métricas HTTP."""
    
    def __init__(self, prometheus_url=None):
        """
        Inicializa o coletor de métricas HTTP.
        
        Args:
            prometheus_url (str): URL do Prometheus
        """
        self.collector = PrometheusCollector(prometheus_url)
    
    def get_response_times(self, service=None, path=None, method=None):
        """
        Obtém tempos de resposta HTTP.
        
        Args:
            service (str): Nome do serviço para filtrar
            path (str): Caminho da rota para filtrar
            method (str): Método HTTP para filtrar
            
        Returns:
            dict: Dados de tempo de resposta
        """
        # Construir filtros
        filters = []
        if service:
            filters.append(f'service="{service}"')
        if path:
            filters.append(f'path="{path}"')
        if method:
            filters.append(f'method="{method}"')
            
        filter_str = ""
        if filters:
            filter_str = f'{{{",".join(filters)}}}'
            
        sum_query = f'{BASIC_METRICS["http_response_time_sum"]}{filter_str}'
        count_query = f'{BASIC_METRICS["http_response_time_count"]}{filter_str}'
        avg_query = f'{sum_query} / {count_query}'
        
        return {
            "sum": self.collector.get_metric_last_value(sum_query),
            "count": self.collector.get_metric_last_value(count_query),
            "avg": self.collector.get_metric_last_value(avg_query)
        }
    
    def get_response_times_over_time(self, hours=1, service=None, path=None, method=None):
        """
        Obtém tempos de resposta HTTP ao longo do tempo.
        
        Args:
            hours (int): Número de horas para olhar para trás
            service (str): Nome do serviço para filtrar
            path (str): Caminho da rota para filtrar
            method (str): Método HTTP para filtrar
            
        Returns:
            dict: Dados de tempo de resposta ao longo do tempo
        """
        # Construir filtros
        filters = []
        if service:
            filters.append(f'service="{service}"')
        if path:
            filters.append(f'path="{path}"')
        if method:
            filters.append(f'method="{method}"')
            
        filter_str = ""
        if filters:
            filter_str = f'{{{",".join(filters)}}}'
            
        sum_query = f'{BASIC_METRICS["http_response_time_sum"]}{filter_str}'
        count_query = f'{BASIC_METRICS["http_response_time_count"]}{filter_str}'
        avg_query = f'{sum_query} / {count_query}'
        
        return {
            "sum": self.collector.get_metric_over_time(sum_query, hours),
            "count": self.collector.get_metric_over_time(count_query, hours),
            "avg": self.collector.get_metric_over_time(avg_query, hours)
        }
