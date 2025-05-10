"""
Script principal para execução da coleta de métricas do Prometheus.
"""
import os
import logging
import argparse
import time
from datetime import datetime

from metrics.metrics.container import ContainerMetricsCollector
from metrics.metrics.http import HttpMetricsCollector
from metrics.processors.data_processor import MetricsDataProcessor
from metrics.exporters.csv_exporter import CSVExporter
from metrics.exporters.json_exporter import JSONExporter
from metrics.collectors.prometheus import PrometheusCollector
from metrics.config import CALCULATED_METRICS

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

def setup_args():
    """Define os argumentos de linha de comando."""
    parser = argparse.ArgumentParser(description='Coleta métricas do Prometheus')
    
    parser.add_argument('--prometheus-url', 
                        help='URL do servidor Prometheus', 
                        default='http://prometheus:9090')
    
    parser.add_argument('--output-dir', 
                        help='Diretório para salvar os dados coletados')
    
    parser.add_argument('--format', 
                        choices=['csv', 'json', 'both'], 
                        default='csv',
                        help='Formato de saída dos dados (padrão: csv)')
    
    parser.add_argument('--namespace', 
                        help='Namespace Kubernetes para filtrar')
    
    parser.add_argument('--container', 
                        help='Nome do container para filtrar')
    
    parser.add_argument('--service', 
                        help='Nome do serviço para filtrar métricas HTTP')
    
    parser.add_argument('--interval', 
                        type=int, 
                        default=0,
                        help='Intervalo em segundos para coleta contínua (0 = coleta única)')
    
    parser.add_argument('--log-level',
                        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
                        default='INFO',
                        help='Nível de log (padrão: INFO)')
    
    parser.add_argument('--stop-on-error',
                        action='store_true',
                        help='Interrompe a coleta em caso de erro')
    
    return parser.parse_args()

def setup_logging(log_level):
    """Configura o nível de log."""
    logging.getLogger().setLevel(log_level)

def collect_and_export(args):
    """
    Coleta e exporta métricas com base nos argumentos fornecidos.
    
    Args:
        args: Argumentos da linha de comando
    """
    # Inicializa coletores
    container_collector = ContainerMetricsCollector(args.prometheus_url)
    http_collector = HttpMetricsCollector(args.prometheus_url)
    
    # Inicializa processador
    processor = MetricsDataProcessor()
    
    # Inicializa exportadores
    exporters = []
    if args.format in ['csv', 'both']:
        exporters.append(CSVExporter(args.output_dir))
    if args.format in ['json', 'both']:
        exporters.append(JSONExporter(args.output_dir))
    
    # Coleta métricas de contêineres
    logger.info("Coletando métricas de contêineres...")
    cpu_data = container_collector.get_cpu_usage(args.container, args.namespace)
    memory_data = container_collector.get_memory_usage(args.container, args.namespace)
    network_data = container_collector.get_network_traffic(args.container, args.namespace)
    cpu_throttling_data = container_collector.get_cpu_throttling(args.container, args.namespace)
    
    # Coleta métricas HTTP
    logger.info("Coletando métricas HTTP...")
    http_data = http_collector.get_response_times(args.service)
    
    # Extrai e processa dados
    results = {}
    
    # Processa métricas de CPU
    if cpu_data:
        results['cpu_usage'] = processor.extract_values(cpu_data)
    
    # Processa métricas de memória
    if memory_data:
        results['memory_usage'] = processor.extract_values(memory_data)
    
    # Processa métricas de rede
    if network_data:
        for direction, data in network_data.items():
            if data:
                results[f'network_{direction}'] = processor.extract_values(data)
    
    # Processa métricas de throttling de CPU
    if cpu_throttling_data:
        for metric_name, data in cpu_throttling_data.items():
            if data:
                results[f'cpu_{metric_name}'] = processor.extract_values(data)
    
    # Processa métricas HTTP
    if http_data:
        for metric_name, data in http_data.items():
            if data:
                results[f'http_{metric_name}'] = processor.extract_values(data)
    
    # Exporta resultados
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    for metric_name, data in results.items():
        if not data:
            continue
            
        # Converte para DataFrame
        df = processor.to_dataframe(data)
        
        if df.empty:
            continue
            
        filename = f"{metric_name}_{timestamp}"
        
        for exporter in exporters:
            if hasattr(exporter, 'export_dataframe'):
                exporter.export_dataframe(df, f"{filename}.{exporter.__class__.__name__.lower().replace('exporter', '')}")

def collect_noisy_neighbour_metrics(args):
    """
    Coleta métricas específicas para análise de noisy neighbours.
    
    Args:
        args: Argumentos da linha de comando
    """
    logger.info("Coletando métricas específicas de noisy neighbours...")
    prometheus_client = PrometheusCollector(args.prometheus_url)
    processor = MetricsDataProcessor()
    
    # Inicializa exportadores
    exporters = []
    if args.format in ['csv', 'both']:
        exporters.append(CSVExporter(args.output_dir))
    if args.format in ['json', 'both']:
        exporters.append(JSONExporter(args.output_dir))
    
    # Métricas específicas para análise de noisy neighbours
    noisy_metrics = [
        "cpu_usage_by_namespace",
        "cpu_usage_by_pod",
        "memory_usage_by_namespace",
        "memory_usage_by_pod",
        "cpu_throttling_by_pod",
        "cpu_usage_percent_limit",
        "memory_usage_percent_limit",
        "tenant_a_to_tenant_c_cpu_ratio",
        "tenant_b_to_tenant_c_cpu_ratio",
        "cpu_saturation",
        "disk_io_utilization",
        "pod_restart_rate"
    ]
    
    results = {}
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    for metric_name in noisy_metrics:
        if metric_name in CALCULATED_METRICS:
            query = CALCULATED_METRICS[metric_name]
            data = prometheus_client.get_metric_last_value(query)
            
            if data:
                results[f'noisy_{metric_name}'] = processor.extract_values(data)
                
                # Exporta o resultado
                df = processor.to_dataframe(results[f'noisy_{metric_name}'])
                if not df.empty:
                    filename = f"noisy_{metric_name}_{timestamp}"
                    for exporter in exporters:
                        if hasattr(exporter, 'export_dataframe'):
                            exporter.export_dataframe(df, f"{filename}.{exporter.__class__.__name__.lower().replace('exporter', '')}")
    
    logger.info("Coleta de métricas de noisy neighbours concluída!")

def main():
    """Função principal."""
    args = setup_args()
    setup_logging(args.log_level)
    
    if args.interval > 0:
        logger.info(f"Coletando métricas a cada {args.interval} segundos...")
        while True:
            try:
                collect_and_export(args)
                collect_noisy_neighbour_metrics(args)  # Adiciona coleta de métricas específicas
                time.sleep(args.interval)
            except KeyboardInterrupt:
                logger.info("Coleta interrompida pelo usuário.")
                break
            except Exception as e:
                logger.error(f"Erro na coleta: {e}")
                if args.stop_on_error:
                    break
    else:
        logger.info("Coletando métricas uma única vez...")
        collect_and_export(args)
        collect_noisy_neighbour_metrics(args)  # Adiciona coleta de métricas específicas

if __name__ == "__main__":
    main()
