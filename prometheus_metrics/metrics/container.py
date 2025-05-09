"""
Coletor de métricas específicas de contêineres.
"""
import logging
from prometheus_metrics.collector import PrometheusCollector
from prometheus_metrics.config import BASIC_METRICS, CALCULATED_METRICS

logger = logging.getLogger(__name__)

class ContainerMetricsCollector:
    """Classe para coletar métricas específicas de contêineres."""
    
    def __init__(self, prometheus_url=None):
        """
        Inicializa o coletor de métricas de contêineres.
        
        Args:
            prometheus_url (str): URL do Prometheus
        """
        self.collector = PrometheusCollector(prometheus_url)
    
    def get_cpu_usage(self, container_name=None, namespace=None):
        """
        Obtém o uso de CPU para contêineres.
        
        Args:
            container_name (str): Nome do contêiner para filtrar
            namespace (str): Namespace para filtrar
            
        Returns:
            dict: Dados de uso de CPU
        """
        query = BASIC_METRICS["container_cpu"]
        
        # Adiciona filtros se fornecidos
        filters = []
        if container_name:
            filters.append(f'container="{container_name}"')
        if namespace:
            filters.append(f'namespace="{namespace}"')
            
        if filters:
            query = f'{query}{{{",".join(filters)}}}'
            
        return self.collector.get_metric_last_value(query)
    
    def get_memory_usage(self, container_name=None, namespace=None):
        """
        Obtém o uso de memória para contêineres.
        
        Args:
            container_name (str): Nome do contêiner para filtrar
            namespace (str): Namespace para filtrar
            
        Returns:
            dict: Dados de uso de memória
        """
        query = BASIC_METRICS["container_memory"]
        
        # Adiciona filtros se fornecidos
        filters = []
        if container_name:
            filters.append(f'container="{container_name}"')
        if namespace:
            filters.append(f'namespace="{namespace}"')
            
        if filters:
            query = f'{query}{{{",".join(filters)}}}'
            
        return self.collector.get_metric_last_value(query)
    
    def get_network_traffic(self, container_name=None, namespace=None):
        """
        Obtém o tráfego de rede para contêineres.
        
        Args:
            container_name (str): Nome do contêiner para filtrar
            namespace (str): Namespace para filtrar
            
        Returns:
            dict: Dados de tráfego de rede (rx e tx)
        """
        result = {}
        
        for direction in ["rx", "tx"]:
            metric_key = f"container_network_{direction}"
            query = BASIC_METRICS[metric_key]
            
            # Adiciona filtros se fornecidos
            filters = []
            if container_name:
                filters.append(f'container="{container_name}"')
            if namespace:
                filters.append(f'namespace="{namespace}"')
                
            if filters:
                query = f'{query}{{{",".join(filters)}}}'
                
            result[direction] = self.collector.get_metric_last_value(query)
            
        return result
    
    def get_cpu_throttling(self, container_name=None, namespace=None):
        """
        Obtém dados de throttling de CPU para contêineres.
        
        Args:
            container_name (str): Nome do contêiner para filtrar
            namespace (str): Namespace para filtrar
            
        Returns:
            dict: Dados de throttling de CPU
        """
        # Construir a consulta para a razão de throttling diretamente como expressão PromQL
        filters = []
        if container_name:
            filters.append(f'container="{container_name}"')
        if namespace:
            filters.append(f'namespace="{namespace}"')
            
        filter_str = ""
        if filters:
            filter_str = f'{{{",".join(filters)}}}'
            
        throttled_query = f'{BASIC_METRICS["container_cpu_throttled_periods"]}{filter_str}'
        periods_query = f'{BASIC_METRICS["container_cpu_periods"]}{filter_str}'
        ratio_query = f'{throttled_query} / {periods_query}'
        
        return {
            "throttled_periods": self.collector.get_metric_last_value(throttled_query),
            "periods": self.collector.get_metric_last_value(periods_query),
            "throttling_ratio": self.collector.get_metric_last_value(ratio_query)
        }
