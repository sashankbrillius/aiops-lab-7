#!/bin/bash
set -e

# Create log directory
mkdir -p /lab/run

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "=== Shutting down services ==="
    kill $(jobs -p) 2>/dev/null || true
    wait
    echo "All services stopped."
    exit 0
}

# Trap signals
trap cleanup SIGTERM SIGINT

# Function to start a service in background
start_service() {
    local name=$1
    local cmd=$2
    echo "Starting $name..."
    $cmd > /lab/run/${name}.log 2>&1 &
    echo "$!" > /lab/run/${name}.pid
    sleep 2
    if ! kill -0 $(cat /lab/run/${name}.pid) 2>/dev/null; then
        echo "ERROR: $name failed to start. Check /lab/run/${name}.log"
        tail -20 /lab/run/${name}.log
        exit 1
    fi
    echo "  ✓ $name started (PID: $(cat /lab/run/${name}.pid))"
}

echo "=========================================="
echo "  SmartDine AIOps Lab - Starting Services"
echo "=========================================="
echo ""

# Start Loki first (needed by Promtail)
start_service "loki" "/usr/local/bin/loki -config.file=/lab/loki/loki-config.yaml"

# Start Promtail (depends on Loki)
start_service "promtail" "/usr/local/bin/promtail -config.file=/lab/promtail/promtail-config.yaml"

# Start Jaeger (needed by OTel collector)
start_service "jaeger" "/usr/local/bin/jaeger-all-in-one --query.base-path=/"

# Start OTel Collector (depends on Jaeger)
start_service "otel-collector" "/usr/local/bin/otel-collector --config=/lab/otel-collector/otel-collector-config.yaml"

# Start Prometheus
start_service "prometheus" "/usr/local/bin/prometheus --config.file=/lab/prometheus/prometheus.yml --storage.tsdb.path=/lab/prometheus/data --web.enable-lifecycle"

# Start Grafana (depends on Prometheus and Loki)
start_service "grafana" "/usr/sbin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini --packaging=deb cfg:default.paths.logs=/var/log/grafana cfg:default.paths.data=/var/lib/grafana cfg:default.paths.plugins=/var/lib/grafana/plugins cfg:default.paths.provisioning=/lab/grafana/provisioning"

# Start AIOps Engine
cd /lab/aiops-engine
start_service "aiops-engine" "python3 app.py"

# Start Kitchen API
cd /lab/kitchen-api
export PORT=5101
export SERVICE_NAME=kitchen-api
export ENV=lab
export OWNER=platform
export VERSION=v1.3
export CHANGE_ID=MENU-200
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
export OTEL_LOG_LEVEL=info
export LOG_FILE=/var/log/kitchen/app.log
start_service "kitchen-api" "node src/index.js"

# Start ttyd web terminal
start_service "ttyd" "/usr/local/bin/ttyd -p 5102 -t titleFixed='SmartDine AIOps Lab Terminal' -t fontSize=14 /bin/bash"

echo ""
echo "=========================================="
echo "  Service Endpoints"
echo "=========================================="
echo "  Kitchen API:      http://localhost:5101/health"
echo "  AIOps Engine:     http://localhost:7000/status"
echo "  Prometheus:       http://localhost:9090"
echo "  Grafana:          http://localhost:3000 (admin/admin)"
echo "  Loki:             http://localhost:3100/ready"
echo "  Jaeger UI:        http://localhost:16686"
echo "  Web Terminal:     http://localhost:5102"
echo "=========================================="
echo ""
echo "All services are running. Logs are in /lab/run/*.log"
echo "Press Ctrl+C to stop all services."
echo ""

# Keep container alive and monitor processes
while true; do
    sleep 5
    # Check if any critical service died
    for pidfile in /lab/run/*.pid; do
        if [ -f "$pidfile" ]; then
            pid=$(cat "$pidfile")
            if ! kill -0 "$pid" 2>/dev/null; then
                echo "WARNING: Service $(basename $pidfile .pid) died. Check logs."
            fi
        fi
    done
done

