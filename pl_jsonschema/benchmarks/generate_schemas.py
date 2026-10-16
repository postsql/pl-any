#!/usr/bin/env python3
"""
generate_schemas.py: Schema Generator for GitHub Archive JSON Logs

Extracts JSON logs from github_archive (either local 2025-01-15-14.json or remote stream),
infers JSON Schema (Draft-07), Apache Avro (.avsc), and SQL schemas (PostgreSQL)
per event type, and builds unified schemas for Avro, JSON Schema, and SQL.
"""

import argparse
import copy
import gzip
import json
import os
import re
import subprocess
import urllib.request

EVENTS = [
    "CommitCommentEvent",
    "CreateEvent",
    "DeleteEvent",
    "ForkEvent",
    "GollumEvent",
    "IssueCommentEvent",
    "IssuesEvent",
    "MemberEvent",
    "PublicEvent",
    "PullRequestEvent",
    "PullRequestReviewCommentEvent",
    "PullRequestReviewEvent",
    "PushEvent",
    "ReleaseEvent",
    "WatchEvent",
]

DEFAULT_LOCAL_PATH = os.path.expanduser("~/JSON-DATA/2025-01-15-14.json")
REMOTE_ARCHIVE_URL = "https://data.gharchive.org/2025-01-15-14.json.gz"

ISO_DATETIME_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"
)


# ==============================================================================
# 1. JSON Schema Inference & Merging
# ==============================================================================

def merge_schemas(s1, s2):
  """Merges two JSON Schema definitions into a unified superset schema."""
  if not s1:
    return copy.deepcopy(s2) if s2 else {}
  if not s2:
    return copy.deepcopy(s1)

  t1 = s1.get("type", [])
  t2 = s2.get("type", [])
  if isinstance(t1, str):
    t1 = [t1]
  if isinstance(t2, str):
    t2 = [t2]

  types = sorted(set(t1) | set(t2))
  # Numeric promotion: if both integer and number, keep number
  if "integer" in types and "number" in types:
    types.remove("integer")

  merged = {"type": types[0] if len(types) == 1 else types}

  # Merge object properties recursively
  if "object" in types:
    props = dict(s1.get("properties", {}))
    for k, v in s2.get("properties", {}).items():
      props[k] = merge_schemas(props.get(k), v)
    merged["properties"] = props

  # Merge array item schemas cleanly without fallback pollution
  if "array" in types:
    it1 = s1.get("items")
    it2 = s2.get("items")
    if it1 and it2:
      merged["items"] = merge_schemas(it1, it2)
    elif it1:
      merged["items"] = copy.deepcopy(it1)
    elif it2:
      merged["items"] = copy.deepcopy(it2)

  # Preserve format if present
  if "format" in s1 and "format" in s2 and s1["format"] == s2["format"]:
    merged["format"] = s1["format"]
  elif "format" in s1 and "format" not in s2:
    merged["format"] = s1["format"]
  elif "format" in s2 and "format" not in s1:
    merged["format"] = s2["format"]

  return merged


def infer_schema(val):
  """Infers a Draft-07 JSON schema node from a python value."""
  if val is None:
    return {"type": "null"}
  # bool must be checked before int because bool inherits from int in Python
  if isinstance(val, bool):
    return {"type": "boolean"}
  if isinstance(val, int):
    return {"type": "integer"}
  if isinstance(val, float):
    return {"type": "number"}
  if isinstance(val, str):
    if ISO_DATETIME_RE.match(val):
      return {"type": "string", "format": "date-time"}
    return {"type": "string"}
  if isinstance(val, list):
    item_schema = {}
    for item in val:
      item_schema = merge_schemas(item_schema, infer_schema(item))
    # Return pure array if empty; do not inject false string fallback here
    if item_schema:
      return {"type": "array", "items": item_schema}
    return {"type": "array"}
  if isinstance(val, dict):
    return {
        "type": "object",
        "properties": {k: infer_schema(v) for k, v in val.items()},
    }
  return {"type": "string"}


# ==============================================================================
# 2. JSON Schema -> Apache Avro (.avsc) Converter
# ==============================================================================

def sanitize_avro_name(name):
  """Sanitizes field and record names to conform to Avro regex [A-Za-z_][A-Za-z0-9_]*."""
  if name == "+1":
    return "plus_1"
  if name == "-1":
    return "minus_1"
  s = re.sub(r"[^A-Za-z0-9_]", "_", name)
  if not s or s[0].isdigit():
    s = "_" + s
  return s


def json_schema_to_avro_type(js_node, record_name, is_root=False):
  """Recursively converts a JSON Schema node into an Apache Avro schema type."""
  if not js_node:
    return ["null", "string"]

  js_types = js_node.get("type", ["string"])
  if isinstance(js_types, str):
    js_types = [js_types]

  avro_branches = []
  for t in js_types:
    if t == "null":
      if "null" not in avro_branches:
        avro_branches.insert(0, "null")
    elif t == "boolean":
      avro_branches.append("boolean")
    elif t == "integer":
      avro_branches.append("long")  # 64-bit int to avoid GitHub ID overflow
    elif t == "number":
      avro_branches.append("double")
    elif t == "string":
      avro_branches.append("string")
    elif t == "array":
      items_node = js_node.get("items")
      if not items_node:
        items_avro = ["null", "string"]
      else:
        items_avro = json_schema_to_avro_type(items_node, f"{record_name}_item")
        if isinstance(items_avro, list):
          if "null" in items_avro:
            items_avro.remove("null")
          items_avro = ["null"] + items_avro
        elif items_avro != "null":
          items_avro = ["null", items_avro]
      avro_branches.append({"type": "array", "items": items_avro})
    elif t == "object":
      props = js_node.get("properties", {})
      if not props:
        if is_root or record_name.endswith("Payload"):
          avro_branches.append({
              "type": "record",
              "name": sanitize_avro_name(record_name),
              "fields": [],
          })
        else:
          avro_branches.append({"type": "map", "values": ["null", "string"]})
      else:
        fields = []
        used_names = set()
        for prop_key, prop_schema in sorted(props.items()):
          safe_name = sanitize_avro_name(prop_key)
          while safe_name in used_names:
            safe_name += "_"
          used_names.add(safe_name)

          field_avro = json_schema_to_avro_type(
              prop_schema, f"{record_name}_{safe_name}"
          )
          if isinstance(field_avro, list):
            if "null" in field_avro:
              field_avro.remove("null")
            field_type = ["null"] + field_avro
          elif field_avro == "null":
            field_type = ["null", "string"]
          else:
            field_type = ["null", field_avro]

          field_def = {
              "name": safe_name,
              "type": field_type,
              "default": None,
          }
          if safe_name != prop_key:
            field_def["doc"] = f"Original JSON key: {prop_key}"
          fields.append(field_def)

        avro_branches.append({
            "type": "record",
            "name": sanitize_avro_name(record_name),
            "fields": fields,
        })

  if not avro_branches:
    return ["null", "string"]
  if len(avro_branches) == 1:
    return avro_branches[0]
  if "null" in avro_branches:
    avro_branches.remove("null")
    avro_branches.insert(0, "null")
  return avro_branches


# ==============================================================================
# 3. SQL Schema Generation (PostgreSQL DDL)
# ==============================================================================

def to_snake_case(name):
  s = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
  return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s).lower()


def map_json_type_to_pg(prop_name, prop_schema):
  """Maps JSON schema types to PostgreSQL column types accurately."""
  types = prop_schema.get("type", ["string"])
  if isinstance(types, str):
    types = [types]
  non_null_types = [t for t in types if t != "null"]
  main_type = non_null_types[0] if non_null_types else "string"

  if main_type == "string":
    p_lower = prop_name.lower()
    if (
        prop_schema.get("format") == "date-time"
        or p_lower.endswith("_at")
        or p_lower.endswith("_time")
        or p_lower.endswith("_date")
        or p_lower in ("created_at", "updated_at", "closed_at", "merged_at", "pushed_at")
    ):
      return "TIMESTAMPTZ"
    return "TEXT"
  elif main_type == "integer":
    return "BIGINT"
  elif main_type == "number":
    return "DOUBLE PRECISION"
  elif main_type == "boolean":
    return "BOOLEAN"
  elif main_type in ("object", "array"):
    return "JSONB"
  return "TEXT"


def generate_event_sql(event_name, schema):
  """Generates a dedicated PostgreSQL CREATE TABLE DDL for a single event type."""
  table_name = f"gh_{to_snake_case(event_name)}"
  payload_props = (
      schema.get("properties", {}).get("payload", {}).get("properties", {})
  )

  cols = [
      "    id BIGINT PRIMARY KEY",
      f"    type VARCHAR(64) NOT NULL DEFAULT '{event_name}'",
      "    public BOOLEAN NOT NULL DEFAULT TRUE",
      "    created_at TIMESTAMPTZ NOT NULL",
      "    actor JSONB",
      "    repo JSONB",
      "    org JSONB",
  ]

  for prop_key, prop_schema in sorted(payload_props.items()):
    col_name = sanitize_avro_name(prop_key)
    pg_type = map_json_type_to_pg(prop_key, prop_schema)
    cols.append(f"    payload_{col_name} {pg_type}")

  cols.append("    raw_payload JSONB")

  sql = [
      f"-- DDL for {event_name} ({table_name})",
      f"CREATE TABLE IF NOT EXISTS {table_name} (",
      ",\n".join(cols),
      ");",
      f"CREATE INDEX IF NOT EXISTS idx_{table_name}_created_at ON {table_name}(created_at);",
      f"CREATE INDEX IF NOT EXISTS idx_{table_name}_repo_id ON {table_name}( ((repo->>'id')::bigint) );",
      f"CREATE INDEX IF NOT EXISTS idx_{table_name}_raw_payload_gin ON {table_name} USING gin (raw_payload jsonb_path_ops);",
      "",
  ]
  return "\n".join(sql)


def generate_union_sql(events, schemas):
  """Generates the Master Union SQL Schema: partitioned table, per-event partitions, and views."""
  lines = [
      "-- ==========================================================================",
      "-- AllEventsUnion.sql: Master PostgreSQL Schema for GitHub Archive Logs",
      "-- Provides partitioned storage across all 15 GitHub event types",
      "-- ==========================================================================",
      "",
      "-- 1. Master Partitioned Table",
      "CREATE TABLE IF NOT EXISTS github_events (",
      "    id BIGINT NOT NULL,",
      "    type VARCHAR(64) NOT NULL,",
      "    public BOOLEAN NOT NULL DEFAULT TRUE,",
      "    created_at TIMESTAMPTZ NOT NULL,",
      "    actor JSONB,",
      "    repo JSONB,",
      "    org JSONB,",
      "    payload JSONB,",
      "    PRIMARY KEY (id, type)",
      ") PARTITION BY LIST (type);",
      "",
      "-- 2. Individual Partitions per Event Type",
  ]

  for ev in events:
    part_name = f"github_events_{to_snake_case(ev).replace('_event', '')}"
    lines.append(
        f"CREATE TABLE IF NOT EXISTS {part_name} PARTITION OF github_events"
        f" FOR VALUES IN ('{ev}');"
    )

  lines.extend([
      "",
      "-- 3. Indexes for Efficient Querying",
      "CREATE INDEX IF NOT EXISTS idx_github_events_created_at ON github_events(created_at);",
      "CREATE INDEX IF NOT EXISTS idx_github_events_type_created_at ON github_events(type, created_at);",
      "CREATE INDEX IF NOT EXISTS idx_github_events_repo_id ON github_events( ((repo->>'id')::bigint) );",
      "CREATE INDEX IF NOT EXISTS idx_github_events_payload_gin ON github_events USING gin (payload jsonb_path_ops);",
      "",
      "-- 4. Typed Per-Event Views Unpacking Common Payload Fields (Includes Raw Payload)",
  ])

  for ev in events:
    view_name = f"v_{to_snake_case(ev)}"
    payload_props = (
        schemas[ev]
        .get("properties", {})
        .get("payload", {})
        .get("properties", {})
    )
    select_cols = [
        "    id",
        "    type",
        "    public",
        "    created_at",
        "    actor",
        "    repo",
        "    org",
    ]
    for prop_key, prop_schema in sorted(payload_props.items()):
      col_name = sanitize_avro_name(prop_key)
      pg_type = map_json_type_to_pg(prop_key, prop_schema)
      if pg_type in ("BIGINT", "INT"):
        select_cols.append(f"    (payload->>'{prop_key}')::bigint AS {col_name}")
      elif pg_type == "BOOLEAN":
        select_cols.append(
            f"    (payload->>'{prop_key}')::boolean AS {col_name}"
        )
      elif pg_type == "DOUBLE PRECISION":
        select_cols.append(f"    (payload->>'{prop_key}')::float8 AS {col_name}")
      elif pg_type == "TIMESTAMPTZ":
        select_cols.append(
            f"    (payload->>'{prop_key}')::timestamptz AS {col_name}"
        )
      elif pg_type == "JSONB":
        select_cols.append(f"    (payload->'{prop_key}') AS {col_name}")
      else:
        select_cols.append(f"    (payload->>'{prop_key}') AS {col_name}")

    select_cols.append("    payload")

    lines.append(f"CREATE OR REPLACE VIEW {view_name} AS")
    lines.append("SELECT")
    lines.append(",\n".join(select_cols))
    lines.append("FROM github_events")
    lines.append(f"WHERE type = '{ev}';")
    lines.append("")

  return "\n".join(lines)


# ==============================================================================
# 4. Main Processing & Execution Pipeline
# ==============================================================================

def run_pipeline(
    input_path=DEFAULT_LOCAL_PATH,
    out_dirs=None,
    max_samples=1000,
    validate=True,
    json_schema_only=False,
):
  if out_dirs is None:
    out_dirs = [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "schemas"),
    ]

  for d in out_dirs:
    os.makedirs(d, exist_ok=True)

  counts = {ev: 0 for ev in EVENTS}
  schemas = {ev: {"type": "object", "properties": {}} for ev in EVENTS}
  envelope_js = {"type": "object", "properties": {}}

  # Determine input source
  if os.path.exists(input_path):
    print(f"Reading local dataset: {input_path}")
    open_fn = (
        (lambda: gzip.open(input_path, "rt"))
        if input_path.endswith(".gz")
        else (lambda: open(input_path, "r", encoding="utf-8"))
    )
    with open_fn() as f:
      for line_num, line in enumerate(f):
        if not line.strip():
          continue
        row = json.loads(line)
        ev_type = row.get("type")
        if ev_type in counts and counts[ev_type] < max_samples:
          if isinstance(row.get("payload"), str):
            row["payload"] = json.loads(row["payload"])
          inferred = infer_schema(row)
          schemas[ev_type] = merge_schemas(schemas[ev_type], inferred)
          envelope_js = merge_schemas(envelope_js, inferred)
          counts[ev_type] += 1
          if all(c >= max_samples for c in counts.values()):
            print(
                f"Reached target sample count of {max_samples} across all"
                f" events at line {line_num}."
            )
            break
  else:
    print(
        f"Local file {input_path} not found. Attempting stream from"
        f" {REMOTE_ARCHIVE_URL} ..."
    )
    req = urllib.request.Request(
        REMOTE_ARCHIVE_URL, headers={"User-Agent": "Mozilla/5.0"}
    )
    with urllib.request.urlopen(req) as resp, gzip.GzipFile(fileobj=resp) as gz:
      for line in gz:
        row = json.loads(line.decode("utf-8"))
        ev_type = row.get("type")
        if ev_type in counts and counts[ev_type] < max_samples:
          if isinstance(row.get("payload"), str):
            row["payload"] = json.loads(row["payload"])
          inferred = infer_schema(row)
          schemas[ev_type] = merge_schemas(schemas[ev_type], inferred)
          envelope_js = merge_schemas(envelope_js, inferred)
          counts[ev_type] += 1
          if all(c >= max_samples for c in counts.values()):
            break

  print("Sampling results:")
  for ev in EVENTS:
    print(f"  {ev}: {counts[ev]} rows sampled")

  payload_union_records = ["null"]
  all_event_definitions = {}

  for ev in EVENTS:
    event_schema = copy.deepcopy(schemas[ev])
    if "properties" in event_schema:
      event_schema["properties"]["type"] = {
          "type": "string",
          "enum": [ev],
          "description": f"Unique discriminator for {ev}",
      }
    event_schema["required"] = ["id", "type", "created_at"]

    js_doc = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "$id": f"https://api.github.com/events/{ev}.schema.json",
        "title": ev,
        "description": f"Draft-07 JSON Schema for GitHub Archive {ev}",
        **event_schema,
    }
    all_event_definitions[ev] = js_doc

    for d in out_dirs:
      with open(os.path.join(d, f"{ev}.schema.json"), "w") as f:
        json.dump(js_doc, f, indent=2)

    if not json_schema_only:
      avro_doc = json_schema_to_avro_type(schemas[ev], ev, is_root=True)
      if isinstance(avro_doc, dict) and avro_doc.get("type") == "record":
        avro_doc["namespace"] = "com.github.archive"

      sql_doc = generate_event_sql(ev, schemas[ev])

      for d in out_dirs:
        with open(os.path.join(d, f"{ev}.avsc"), "w") as f:
          json.dump(avro_doc, f, indent=2)
        with open(os.path.join(d, f"{ev}.sql"), "w") as f:
          f.write(sql_doc)

      payload_js = schemas[ev].get("properties", {}).get("payload", {})
      payload_avro = json_schema_to_avro_type(
          payload_js, f"{ev}Payload", is_root=True
      )
      if isinstance(payload_avro, dict) and payload_avro.get("type") == "record":
        payload_union_records.append(payload_avro)
      elif isinstance(payload_avro, list):
        for b in payload_avro:
          if isinstance(b, dict) and b.get("type") == "record":
            payload_union_records.append(b)

  if not json_schema_only:
    envelope_no_payload = copy.deepcopy(envelope_js)
    envelope_no_payload.get("properties", {}).pop("payload", None)
    master_avro = json_schema_to_avro_type(
        envelope_no_payload, "GitHubArchiveEvent", is_root=True
    )
    master_avro["namespace"] = "com.github.archive"
    master_avro["doc"] = (
        "Master Apache Avro schema for GitHub Archive logs with discriminated"
        " payload union"
    )
    master_avro["fields"].append({
        "name": "payload",
        "type": payload_union_records,
        "default": None,
        "doc": "Discriminated union of all 15 GitHub event payload record types",
    })

    master_js = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "$id": "https://api.github.com/events/AllEventsUnion.schema.json",
        "title": "AllEventsUnion",
        "description": (
            "Unified Draft-07 JSON Schema covering all 15 GitHub Archive event"
            " types with discriminated oneOf union"
        ),
        "type": "object",
        "oneOf": [{"$ref": f"#/definitions/{ev}"} for ev in EVENTS],
        "definitions": all_event_definitions,
    }

    master_sql = generate_union_sql(EVENTS, schemas)

    for d in out_dirs:
      with open(os.path.join(d, "AllEventsUnion.avsc"), "w") as f:
        json.dump(master_avro, f, indent=2)
      with open(os.path.join(d, "AllEventsUnion.schema.json"), "w") as f:
        json.dump(master_js, f, indent=2)
      with open(os.path.join(d, "AllEventsUnion.sql"), "w") as f:
        f.write(master_sql)

  print(f"Successfully wrote generated schemas to: {out_dirs}")

  if validate:
    print("\n--- Validating Generated Schemas ---")
    val_dir = out_dirs[0]
    js_valid = 0
    for fname in os.listdir(val_dir):
      if fname.endswith(".schema.json"):
        with open(os.path.join(val_dir, fname), "r") as f:
          parsed = json.load(f)
          assert "$schema" in parsed
          assert "type" in parsed or "oneOf" in parsed
        js_valid += 1
    print(f"JSON Schema validation: {js_valid} files valid JSON Draft-07.")


if __name__ == "__main__":
  parser = argparse.ArgumentParser(
      description="Generate JSON, Avro, and SQL Schemas for GitHub Archive Logs"
  )
  parser.add_argument(
      "--input",
      default=DEFAULT_LOCAL_PATH,
      help="Path to local .json or .json.gz dataset",
  )
  parser.add_argument(
      "--out-dir",
      "-o",
      action="append",
      dest="out_dirs",
      help="Output directory for generated schemas (can be repeated)",
  )
  parser.add_argument(
      "--max-samples",
      type=int,
      default=1000,
      help="Max samples per event type to infer schema",
  )
  parser.add_argument(
      "--json-schema-only",
      action="store_true",
      help="Only write the 15 per-event .schema.json files",
  )
  parser.add_argument(
      "--no-validate",
      action="store_true",
      help="Skip schema validation",
  )
  args = parser.parse_args()

  run_pipeline(
      input_path=args.input,
      out_dirs=args.out_dirs,
      max_samples=args.max_samples,
      validate=not args.no_validate,
      json_schema_only=args.json_schema_only,
  )
