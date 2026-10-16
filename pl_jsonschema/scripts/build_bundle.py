#!/usr/bin/env python3
"""Builds pl_jsonschema--1.0.sql, pl-jsonschema--1.0.sql, and pl_jsonschema_pgtle--1.0.sql from pl_jsonschema.sql.in and ajv_bundle.sql.gz."""

from __future__ import annotations

import gzip
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXTVERSION = "1.0"
COMMENT = "JSON Schema (Draft 2020-12) trusted procedural language for PostgreSQL on V8 / QuickJS (pl_jsonschema / jsonschema)"


def main() -> None:
    sql_in = (ROOT / "pl_jsonschema.sql.in").read_text(encoding="utf-8")
    ajv_raw = gzip.decompress((ROOT / "ajv_bundle.sql.gz").read_bytes()).decode("utf-8")
    ajv_lines = ajv_raw.splitlines()
    # Strip the SQL wrapper lines (first and last line) from ajv_bundle.sql.gz
    ajv_js = "\n".join(ajv_lines[1:-1])

    canonical_sql = sql_in.replace("__AJV_BUNDLE_JS__", ajv_js)
    kebab_sql = canonical_sql.replace(
        "CREATE EXTENSION pl_jsonschema", "CREATE EXTENSION pl-jsonschema", 1
    )

    body_lines = canonical_sql.splitlines()[3:]
    body = "\n".join(body_lines) + "\n"
    pgtle_sql = (
        "-- Register pl_jsonschema as a Trusted Language Extension (pg_tle)\n"
        "-- Prerequisite: CREATE EXTENSION IF NOT EXISTS pg_tle;\n\n"
        "SELECT pgtle.install_extension(\n"
        "  'pl_jsonschema',\n"
        f"  '{EXTVERSION}',\n"
        f"  '{COMMENT}',\n"
        "$tle_pkg_pl_jsonschema$\n"
        f"{body}"
        "$tle_pkg_pl_jsonschema$\n"
        ");\n"
    )

    (ROOT / f"pl_jsonschema--{EXTVERSION}.sql").write_text(canonical_sql, encoding="utf-8")
    (ROOT / f"pl-jsonschema--{EXTVERSION}.sql").write_text(kebab_sql, encoding="utf-8")
    (ROOT / f"pl_jsonschema_pgtle--{EXTVERSION}.sql").write_text(pgtle_sql, encoding="utf-8")
    print(
        f"Generated pl_jsonschema--{EXTVERSION}.sql, pl-jsonschema--{EXTVERSION}.sql, "
        f"and pl_jsonschema_pgtle--{EXTVERSION}.sql"
    )


if __name__ == "__main__":
    main()
