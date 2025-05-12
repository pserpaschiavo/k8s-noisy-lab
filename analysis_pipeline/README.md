# 📊 analysis_pipeline

This directory contains the complete pipeline for analyzing metrics collected during "Noisy Neighbours" experiments in multi-tenant Kubernetes environments.

## 🔍 What this pipeline does

1. Recursively loads metrics from multiple tenants in `.csv` format (including subdirectories)
2. Performs statistical and stochastic analysis (mean, deviation, skew, kurtosis, stationarity)
3. Calculates correlations (Pearson and Spearman) and generates heatmaps
4. Creates visualizations (time series and distributions) with colorblind-friendly palettes
5. Compares metrics between different experiment phases (baseline, attack, recovery)
6. Compares metrics between different tenants to identify "noisy neighbor" impacts
7. Exports statistical tables in CSV and LaTeX formats for scientific publications
8. Organizes analyses by system categories/components
9. Organizes everything in a modular and easily expandable way

## 🧰 Requirements

- Python 3.8+
- Install dependencies with:

```bash
pip install -r requirements.txt
```

**Minimum requirements:**
- pandas
- numpy
- matplotlib
- seaborn
- scipy
- statsmodels

## 📂 Expected structure

The pipeline expects data organized like this:

```
results/
└── YYYY-MM-DD/
    └── HH-MM-SS/
        └── default-experiment-1/
            └── round-1/
                ├── 1 - Baseline/
                │   ├── tenant-a/
                │   │   └── metrics.csv
                │   ├── tenant-b/
                │   ├── ingress-nginx/
                │   └── ...
                ├── 2 - Attack/
                └── 3 - Recovery/
```

The pipeline now recursively processes all subdirectories within each phase, automatically categorizing metrics based on the directory structure.

## 🚀 How to run

Edit the values in `main.py`:

```python
BASE_DIR = os.getenv("K8S_NOISY_LAB_ROOT", os.path.abspath(os.path.dirname(__file__) + "/..")) 
RESULTS_DIR = os.path.join(BASE_DIR, "results")
EXPERIMENT_NAME = "YYYY-MM-DD/HH-MM-SS/experiment-name"
ROUND = "round-1"
PHASES = ["1 - Baseline", "2 - Attack", "3 - Recovery"]
```

And run:

```bash
python main.py
```

## 📊 Results

### Generated Visualizations

The following files and graphical analyses will be generated:

- **Time Series Charts**:
  - Time series: `plots/<phase>/serie_temporal_<source>.png`
  - Metrics by category: `plots/<phase>/metricas_<source>_<category>.png`
  - X-axis with numbered periods for better readability

- **Distribution Visualizations**:
  - Distributions: `plots/<phase>/dist_<source>_<category>.png`
  - Correlation heatmaps: `plots/<phase>/correlacao_pearson.png`
  - Scatter plots for strong correlations: `plots/<phase>/scatter_<metric1>_vs_<metric2>.png`

- **Phase Comparisons**:
  - Boxplots: `plots/comparacao_fases/boxplot_<metric>_<category>_<source>.png`

- **Tenant Comparisons**:
  - Time series: `plots/comparacao_tenants/comp_<phase>_<metric>.png`
  - Boxplots: `plots/comparacao_tenants/boxplot_<phase>_<metric>.png`
  - Means: `plots/comparacao_tenants/media_<phase>_<metric>.png`

### Statistical Tables

In addition to visualizations, the pipeline now exports tabular data in CSV and LaTeX formats:

- **Descriptive Statistics**:
  - `stats_results/<phase>_summary.{csv,tex}`: mean, median, standard deviation, quartiles, etc.

- **Distribution Analysis**:
  - `stats_results/<phase>_skewkurt.{csv,tex}`: skewness and kurtosis for each metric

- **Stationarity Analysis**:
  - `stats_results/<phase>_adf_test.{csv,tex}`: ADF (Augmented Dickey-Fuller) test results

- **Phase Comparisons**:
  - `stats_results/comparison_means.{csv,tex}`: comparison of means between phases
  - `stats_results/comparison_medians.{csv,tex}`: comparison of medians between phases
  - `stats_results/comparison_std.{csv,tex}`: comparison of standard deviations between phases
  - `stats_results/comparison_skewness.{csv,tex}`: comparison of skewness between phases

LaTeX files can be directly incorporated into scientific papers or technical reports.

## 🔍 Expected Results

When analyzing data from the "Noisy Neighbours" experiment, you should expect to observe:

1. **During the Baseline phase**:
   - Stable behavior of metrics across all tenants
   - Low correlation between metrics from different tenants
   - Balanced distribution of cluster resources

2. **During the Attack phase**:
   - Significant increase in resource consumption by the noisy tenant (tenant-b)
   - Performance degradation in sensitive tenants (tenants a, c, d) evidenced by:
     - Increased response latency in tenant-a (network-sensitive)
     - Increased memory operation time in tenant-c (memory-sensitive)
     - Decreased query throughput in tenant-d (CPU/disk-sensitive)
   - High correlation between tenant-b's resource consumption and degradation metrics of other tenants
   - Positive skewness in performance metric distributions

3. **During the Recovery phase**:
   - Gradual return to baseline values after the noisy tenant's activities cease
   - Possible persistence of residual effects in some system components

The statistical tables and visualizations facilitate the identification of these patterns and the precise quantification of the "noisy neighbor" impact on each type of sensitive workload.

### Data Analysis

After collecting the experiment results, you can analyze them using the analysis pipeline:

1. **Configure the experiment variables**:
   
   Edit the `analysis_pipeline/main.py` file to point to your experiment:
   ```python
   EXPERIMENT_NAME = "YYYY-MM-DD/HH-MM-SS/default-experiment-1"
   ROUND = "round-1"
   PHASES = ["1 - Baseline", "2 - Attack", "3 - Recovery"]
   ```

2. **Run the analysis pipeline**:
   ```bash
   cd analysis_pipeline
   python main.py
   ```

3. **View the results**:
   
   The results will be organized in the following folders:
   ```
   plots/                           # Basic visualizations
   ├── 1_-_Baseline/                # Charts from the baseline phase
   ├── 2_-_Attack/                  # Charts from the attack phase
   ├── 3_-_Recovery/                # Charts from the recovery phase
   └── comparacao_fases/            # Comparisons between phases
   
   plots/time_series_analysis/      # Advanced time series analyses
   ├── cross_corr_*.png             # Cross-correlation graphs
   ├── lag_analysis_*.png           # Lag analyses
   └── entropy_*.png                # Entropy analyses
   
   stats_results/                   # Statistical results in CSV and LaTeX
   ├── granger_*.csv                # Granger causality results
   └── entropy_*.csv                # Entropy analysis results
   ```

The pipeline provides:
- Complete statistical analysis of metrics by tenant and component
- Correlations between different metrics (identifying cause-effect relationships)
- Advanced time series analyses to detect complex patterns:
  - **Cross-correlation**: Identifies correlations considering different time lags
  - **Lag analysis**: Determines the optimal delay between related events
  - **Granger causality**: Statistically evaluates if one time series causes another
  - **Entropy analysis**: Quantifies the complexity and regularity of the series
- Comparative graphs between experiment phases
- Automatic identification of metrics with significant variation during attacks

For more details about data analysis, see the [pipeline documentation](analysis_pipeline/README.md).

---

## Metrics Collected

The experiment collects various metrics to analyze the noisy neighbor effect:

### Tenant A (Network-Sensitive)
- Network latency and jitter.
- HTTP response times.
- Connection throughput and errors.
- TCP retransmission rates.

### Tenant B (Noisy Neighbor)
- CPU and memory consumption.
- Network bandwidth utilization.
- I/O operations and throughput.

### Tenant C (Memory-Sensitive)
- Memory usage and allocation.
- Redis operation latency.
- Cache hit/miss rates.
- Memory pressure indicators.

### Tenant D (CPU and Disk-Sensitive)
- Query execution times.
- Transaction throughput.
- I/O wait times.
- CPU throttling events.

### System-wide Metrics
- Node CPU, memory, and I/O utilization.
- Network saturation.
- Kubernetes scheduler decisions.
- Resource contention indicators.

Metrics are collected at configurable intervals (default: 5 seconds) and stored in CSV format for analysis.

---

## Advanced Statistical Techniques

The analysis pipeline implements the following advanced statistical techniques for time series analysis:

### Cross-Correlation
- **Objective**: Identify correlations between time series considering time lags
- **Application**: Detect how one tenant's activity affects others with temporal delay
- **Output**: Graphs showing correlation coefficients for different lags
- **Interpretation**: Peaks in the graph indicate lags where the relationship is strongest

### Lag Analysis
- **Objective**: Determine the optimal temporal delay between related events
- **Application**: Quantify how long it takes for the noisy neighbor impact to be observed
- **Output**: Comparative time series graphs with visual indication of the optimal lag
- **Interpretation**: The lag with the highest correlation represents the delay in effect propagation

### Granger Causality
- **Objective**: Statistically test if one time series "causes" another
- **Application**: Verify if the noisy tenant (B) metrics actually cause degradation in others
- **Output**: Tables with p-values for different lags, indicating statistical significance
- **Interpretation**: P-values < 0.05 indicate causal relationship with 95% statistical confidence

### Entropy Analysis
- **Objective**: Quantify the regularity and complexity of time series
- **Methods**:
  - **Approximate Entropy (ApEn)**: Measures the predictability of patterns in time series
  - **Sample Entropy (SampEn)**: More robust version of ApEn, less sensitive to sample size
- **Application**: 
  - Identify changes in metric behavior complexity during attacks
  - Compare regularity of metrics between different tenants
- **Output**: Bar graphs comparing entropy between different series
- **Interpretation**: 
  - Higher entropy: more irregular/complex/unpredictable behavior
  - Lower entropy: more regular/predictable behavior

These analyses allow identification of more subtle patterns and causal relationships that would not be evident with basic statistical techniques, providing deeper insights into how tenants interact in a shared Kubernetes environment.

---

## 📋 Added features

- **Recursive subdirectory processing**: Automatically analyzes all metric subfolders
- **Automatic categorization**: Uses directory structure to categorize metrics
- **Component-based analysis**: Separates analyses by category (tenant, ingress, etc.)
- **Enriched metadata**: Adds source and path information to metrics
- **Detection of significant correlations**: Automatically highlights strong correlations
- **Phase comparison**: Comparative statistical analysis between baseline, attack, and recovery
- **Tenant comparison**: Directly compares similar metrics between different tenants
- **Numbered periods on X-axis**: Improves readability of time series charts
- **Table export**: Generates statistical tables in CSV and LaTeX formats
- **Improved output organization**: Organized directory structure for results

---

## 📄 License
MIT