FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    jq \
    bash \
    ca-certificates \
    python3 \
    python3-pip \
    supervisor \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 18
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Prometheus
ENV PROMETHEUS_VERSION=2.54.1
RUN cd /tmp && \
    wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && \
    tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && \
    mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/ && \
    mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/ && \
    rm -rf prometheus-${PROMETHEUS_VERSION}*

# Install Grafana OSS
ENV GRAFANA_VERSION=11.2.0
RUN cd /tmp && \
    wget -q https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb && \
    apt-get install -y ./grafana_${GRAFANA_VERSION}_amd64.deb && \
    rm -f grafana_${GRAFANA_VERSION}_amd64.deb && \
    rm -rf /var/lib/apt/lists/*

# Install Loki
ENV LOKI_VERSION=3.1.1
RUN cd /tmp && \
    wget -q https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip && \
    unzip -q loki-linux-amd64.zip && \
    mv loki-linux-amd64 /usr/local/bin/loki && \
    chmod +x /usr/local/bin/loki && \
    rm -f loki-linux-amd64.zip

# Install Promtail
ENV PROMTAIL_VERSION=3.1.1
RUN cd /tmp && \
    wget -q https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip && \
    unzip -q promtail-linux-amd64.zip && \
    mv promtail-linux-amd64 /usr/local/bin/promtail && \
    chmod +x /usr/local/bin/promtail && \
    rm -f promtail-linux-amd64.zip

# Install OpenTelemetry Collector
ENV OTEL_VERSION=0.104.0
RUN cd /tmp && \
    wget -q https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz && \
    tar xzf otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz && \
    mv otelcol-contrib /usr/local/bin/otel-collector && \
    chmod +x /usr/local/bin/otel-collector && \
    rm -f otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz

# Install Jaeger All-in-One
ENV JAEGER_VERSION=1.57
RUN cd /tmp && \
    wget -q https://github.com/jaegertracing/jaeger/releases/download/v${JAEGER_VERSION}/jaeger-${JAEGER_VERSION}-linux-amd64.tar.gz && \
    tar xzf jaeger-${JAEGER_VERSION}-linux-amd64.tar.gz && \
    mv jaeger-${JAEGER_VERSION}-linux-amd64/jaeger-all-in-one /usr/local/bin/ && \
    chmod +x /usr/local/bin/jaeger-all-in-one && \
    rm -rf jaeger-${JAEGER_VERSION}*

# Install ttyd
RUN cd /tmp && \
    wget -q https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 && \
    mv ttyd.x86_64 /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd && \
    rm -rf /tmp/*

# Create lab directory and copy repo
WORKDIR /lab
COPY . .

# Install Node.js dependencies for kitchen-api
WORKDIR /lab/kitchen-api
RUN npm install --omit=dev

# Install Python dependencies for aiops-engine
WORKDIR /lab/aiops-engine
RUN pip3 install --no-cache-dir -r requirements.txt

# Create directories for logs and runtime
RUN mkdir -p /lab/run /lab/logs /var/log/kitchen /loki/chunks /loki/rules /tmp/positions /lab/prometheus/data && \
    chown -R grafana:grafana /var/lib/grafana /var/log/grafana 2>/dev/null || true

# Make start script executable
RUN chmod +x /lab/start_all.sh

# Expose all service ports
EXPOSE 5101 7000 9090 3000 3100 4317 4318 16686 5102

# Set entrypoint
ENTRYPOINT ["/lab/start_all.sh"]

