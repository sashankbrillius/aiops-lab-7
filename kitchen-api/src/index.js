import fs from "node:fs";
import path from "node:path";
import express from "express";
import pino from "pino";
import pinoHttp from "pino-http";
import client from "prom-client";
import { trace, context } from "@opentelemetry/api";
import { startTelemetry } from "./telemetry.js";

await startTelemetry();
const tracer = trace.getTracer("kitchen-api");
const PORT = Number(process.env.PORT || 5101);
const SERVICE = process.env.SERVICE_NAME || "kitchen-api";
const ENV = process.env.ENV || "lab";
const OWNER = process.env.OWNER || "unknown";
const VERSION = process.env.VERSION || "v1.0";
const CHANGE_ID = process.env.CHANGE_ID || "none";
const LOG_FILE = process.env.LOG_FILE || "/var/log/kitchen/app.log";

// Ensure log directory exists
try {
  fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true });
} catch (err) {
  // Fall back to stdout-only logging if directory can't be created
  console.warn("failed to prepare log directory", err);
}

const logStream = fs.createWriteStream(LOG_FILE, { flags: "a" });

// pino multi-destination (stdout + file)
const logger = pino(
  { level: process.env.LOG_LEVEL || "info" },
  pino.multistream([
    { stream: process.stdout },
    { stream: logStream },
  ])
);

// Prometheus metrics
client.collectDefaultMetrics();

const prepTime = new client.Histogram({
  name: "smartdine_prep_time_ms",
  help: "Simulated kitchen prep time in ms",
  labelNames: ["region", "recipe_version", "change_id"],
  buckets: [50, 80, 120, 180, 250, 350, 500, 800, 1200, 2000],
});

const refunds = new client.Counter({
  name: "smartdine_refunds_total",
  help: "Refunds caused by food quality incidents",
  labelNames: ["region", "reason", "change_id"],
});

const app = express();
app.use(express.json({ limit: "256kb" }));

// HTTP logging middleware (adds trace_id/span_id if present)
app.use(
  pinoHttp({
    logger,
    customProps: () => {
      try {
        const span = trace.getSpan(context.active());
        const sc = span?.spanContext();
        return {
          service: SERVICE,
          env: ENV,
          owner: OWNER,
          version: VERSION,
          change_id: CHANGE_ID,
          trace_id: sc?.traceId,
          span_id: sc?.spanId,
        };
      } catch (e) {
        // Never break requests because logging/tracing isn't ready
        logger.warn({ err: e }, "failed to enrich log context; using defaults");
        return {
          service: SERVICE,
          env: ENV,
          owner: OWNER,
          version: VERSION,
          change_id: CHANGE_ID,
        };
      }
    },
  })
);


// In-memory change timeline
const changeTimeline = [];

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    service: SERVICE,
    env: ENV,
    owner: OWNER,
    version: VERSION,
    change_id: CHANGE_ID,
  });
});

app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", client.register.contentType);
  res.send(await client.register.metrics());
});

app.post("/change", (req, res) => {
  const body = req.body || {};
  const event = {
    ts: new Date().toISOString(),
    change_id: String(body.change_id || CHANGE_ID),
    version: String(body.version || VERSION),
    owner: String(body.owner || OWNER),
    description: String(body.description || ""),
  };
  changeTimeline.push(event);

  req.log.info({ event_type: "CHANGE_EVENT", ...event }, "CHANGE_EVENT");
  res.json({ status: "ok", event });
});

app.get("/changes", (_req, res) => {
  res.json({ count: changeTimeline.length, changes: changeTimeline.slice(-50).reverse() });
});

// Simulated order endpoint with trace + metrics + logs
app.get("/order", async (req, res) => {
  const region = (req.query.region || "west").toString();
  const recipeVersion = process.env.RECIPE_VERSION || VERSION;

  tracer.startActiveSpan("order_journey", async (span) => {
    try {
      span.setAttribute("region", region);
      const sc = span.spanContext();
req.log = req.log.child({ trace_id: sc.traceId, span_id: sc.spanId });



  // Base prep time
  let base = region === "east" ? 140 : 90;

  // Bad change: v1.4 in east slows + refunds more likely
  const isBad = recipeVersion === "v1.4" && region === "east";
  if (isBad) base += 260;

  // jitter
  const jitter = Math.floor(Math.random() * 60) - 20;
  const prepMs = Math.max(20, base + jitter);

  // simulate work
  await new Promise((r) => setTimeout(r, prepMs));

  // refunds probability
  let refund = false;
  let reason = "none";
  const roll = Math.random();

  if (isBad && roll < 0.28) {
    refund = true;
    reason = "undercooked_chicken";
  } else if (!isBad && roll < 0.03) {
    refund = true;
    reason = "late_delivery";
  }

  // metrics
  prepTime.labels(region, recipeVersion, CHANGE_ID).observe(prepMs);
  if (refund) refunds.labels(region, reason, CHANGE_ID).inc();

  // log
  if (refund) {
    req.log.warn(
      {
        tag: "REFUND_TAG",
        region,
        prep_time_ms: prepMs,
        reason,
        recipe_version: recipeVersion,
        change_id: CHANGE_ID,
      },
      "REFUND_TAG"
    );
  } else {
    req.log.info(
      {
        region,
        prep_time_ms: prepMs,
        recipe_version: recipeVersion,
        change_id: CHANGE_ID,
      },
      "order_ok"
    );
  }

      res.json({ ok: true, region });
    } catch (e) {
      span.recordException(e);
      req.log.error({ err: e, region, change_id: CHANGE_ID }, "order_failed");
      res.status(500).json({ ok: false, error: String(e) });
    } finally {
      span.end();
    }
  });
});




// Boot
const sdk = await startTelemetry();
process.on("SIGTERM", async () => {
  try {
    await sdk.shutdown();
  } finally {
    process.exit(0);
  }
});

app.listen(PORT, () => {
  logger.info(
    {
      service: SERVICE,
      env: ENV,
      owner: OWNER,
      version: VERSION,
      change_id: CHANGE_ID,
      port: PORT,
      log_file: LOG_FILE,
    },
    "kitchen-api up"
  );
});


