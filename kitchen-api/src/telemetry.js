import { NodeSDK } from "@opentelemetry/sdk-node";
import resourcesPkg from "@opentelemetry/resources";
import { SemanticResourceAttributes as SRA } from "@opentelemetry/semantic-conventions";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";

const { Resource } = resourcesPkg;

/**
 * Starts OpenTelemetry for the Kitchen API.
 *
 * Notes:
 * - We intentionally use Resource (not resourceFromAttributes) to avoid
 *   version / module-format differences in @opentelemetry/resources.
 */
export async function startTelemetry() {
  const serviceName = process.env.SERVICE_NAME || "kitchen-api";
  const env = process.env.ENV || "lab";
  const version = process.env.VERSION || "v1.0";
  const changeId = process.env.CHANGE_ID || "none";
  const owner = process.env.OWNER || "unknown";

  const otlpBase = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || "http://127.0.0.1:4318";
  const traceExporter = new OTLPTraceExporter({
    url: `${otlpBase.replace(/\/$/, "")}/v1/traces`,
  });

  const resource = new Resource({
    [SRA.SERVICE_NAME]: serviceName,
    [SRA.DEPLOYMENT_ENVIRONMENT]: env,
    [SRA.SERVICE_VERSION]: version,
    "change_id": changeId,
    "owner": owner,
  });

  const sdk = new NodeSDK({
    resource,
    traceExporter,
    instrumentations: [
      getNodeAutoInstrumentations({
        // keep it simple for labs
        "@opentelemetry/instrumentation-fs": { enabled: false },
      }),
    ],
  });

  await sdk.start();
  return sdk;
}
