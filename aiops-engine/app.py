import os, json
import numpy as np
from flask import Flask, request, jsonify
from sklearn.ensemble import IsolationForest
import joblib
from prometheus_client import Gauge, generate_latest, CONTENT_TYPE_LATEST

APP = Flask(__name__)

MODEL_PATH = "/app/model.joblib"
model = None

g_anom = Gauge("aiops_anomaly_score", "Anomaly score (0-1)", ["region"])
g_inc  = Gauge("aiops_incident_active", "1 if incident active else 0", ["region"])

def read_events(log_path: str, tail: int = 5000):
  # read last N lines to keep it fast
  with open(log_path, "rb") as f:
    f.seek(0, 2)
    size = f.tell()
    step = min(size, 1024 * 1024)
    data = b""
    while len(data.splitlines()) < tail and f.tell() > 0:
      f.seek(max(0, f.tell() - step))
      data = f.read(step) + data
      f.seek(max(0, f.tell() - step))
      if f.tell() == 0:
        break
  lines = data.splitlines()[-tail:]
  out = []
  for b in lines:
    try:
      o = json.loads(b.decode("utf-8", errors="ignore"))
    except Exception:
      continue
    msg = o.get("msg")
    if msg not in ("order_ok", "REFUND_TAG"):
      continue
    if "prep_time_ms" not in o or "region" not in o:
      continue
    refund = 1 if msg == "REFUND_TAG" else 0
    out.append({
      "region": o.get("region"),
      "prep_time_ms": float(o.get("prep_time_ms")),
      "refund": refund,
      "change_id": o.get("change_id", "none"),
      "recipe_version": o.get("recipe_version", "unknown"),
      "time": o.get("time"),
    })
  return out

def to_X(events):
  # features for model: prep_time_ms, refund, region_is_east
  X = []
  for e in events:
    region_is_east = 1.0 if str(e["region"]).lower() == "east" else 0.0
    X.append([e["prep_time_ms"], float(e["refund"]), region_is_east])
  return np.array(X, dtype=np.float32)

@APP.get("/metrics")
def metrics():
  return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

@APP.post("/train_from_logs")
def train():
  global model
  body = request.get_json(force=True)
  log_path = body.get("log_path", "/var/log/kitchen/app.log")
  baseline_change = (body.get("filter") or {}).get("change_id")
  contamination = float(body.get("contamination", 0.05))
  min_samples = int(body.get("min_samples", 50))
  tail = int(body.get("tail", 5000))

  events = read_events(log_path, tail=tail)
  if baseline_change:
    events = [e for e in events if e["change_id"] == baseline_change]

  if len(events) < min_samples:
    return jsonify({"ok": False, "error": f"not enough samples: {len(events)} (<{min_samples})"}), 400

  X = to_X(events)
  model = IsolationForest(n_estimators=200, contamination=contamination, random_state=42)
  model.fit(X)
  joblib.dump(model, MODEL_PATH)

  return jsonify({"ok": True, "trained_on": len(events), "features": ["prep_time_ms","refund","region_is_east"]})

@APP.post("/score_from_logs")
def score():
  global model
  body = request.get_json(force=True)
  log_path = body.get("log_path", "/var/log/kitchen/app.log")
  tail = int(body.get("tail", 400))
  threshold = float(body.get("threshold", 0.70))

  if model is None and os.path.exists(MODEL_PATH):
    model = joblib.load(MODEL_PATH)
  if model is None:
    return jsonify({"ok": False, "error": "model not trained"}), 400

  events = read_events(log_path, tail=tail)
  if not events:
    return jsonify({"ok": False, "error": "no events found"}), 400

  X = to_X(events)
  # decision_function: higher = more normal -> convert to anomaly score 0..1
  raw = -model.decision_function(X)
  raw = (raw - raw.min()) / (raw.max() - raw.min() + 1e-9)

  # update per-region gauges
  by_region = {}
  for e, s in zip(events, raw):
    r = str(e["region"]).lower()
    by_region.setdefault(r, []).append(float(s))

  out = []
  for r, scores in by_region.items():
    avg = float(np.mean(scores))
    active = 1.0 if avg >= threshold else 0.0
    g_anom.labels(region=r).set(avg)
    g_inc.labels(region=r).set(active)
    out.append({"region": r, "avg_anomaly_score": avg, "incident_active": bool(active), "n": len(scores)})

  return jsonify({"ok": True, "regions": out, "threshold": threshold})

@APP.get("/status")
def status():
  return jsonify({"ok": True, "model_loaded": model is not None})
  
if __name__ == "__main__":
  APP.run(host="0.0.0.0", port=7000)
