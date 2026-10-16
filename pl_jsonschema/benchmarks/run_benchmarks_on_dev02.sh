#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_PLJSON="${LOCAL_PLJSON:-$(dirname "$SCRIPT_DIR")}"
SCHEMAS_DIR="${SCHEMAS_DIR:-$SCRIPT_DIR/schemas}"
JSON_DATA="${JSON_DATA:-$HOME/JSON-DATA/2025-01-15-14.json}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR}"
REMOTE_HOST="${REMOTE_HOST:-dev02}"
TARBALL="$OUT_DIR/dev02_bench_bundle.tar.gz"

echo "=== [0/3] Packaging pl_jsonschema and 15 event schemas ==="
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
mkdir -p "$STAGE_DIR/pl-jsonschema" "$STAGE_DIR/schemas"
cp -r "$LOCAL_PLJSON/"* "$STAGE_DIR/pl-jsonschema/"
cp -r "$SCHEMAS_DIR/"*.schema.json "$STAGE_DIR/schemas/"
if [ -n "${PLJS_PATCHED:-}" ] && [ -d "${PLJS_PATCHED}" ]; then
  mkdir -p "$STAGE_DIR/pljs-patched"
  cp -r "$PLJS_PATCHED/"* "$STAGE_DIR/pljs-patched/"
fi
tar -czf "$TARBALL" -C "$STAGE_DIR" .

echo "=== [1/3] Transferring bundle and dataset (if needed) to $REMOTE_HOST ==="
ssh "$REMOTE_HOST" "mkdir -p ~/bench_jsonschema ~/JSON-DATA"
scp "$TARBALL" "$REMOTE_HOST":~/bench_jsonschema/bundle.tar.gz

if ! ssh "$REMOTE_HOST" "test -f ~/JSON-DATA/2025-01-15-14.json && test \$(stat -c%s ~/JSON-DATA/2025-01-15-14.json) -eq 1039410676"; then
  echo "Transferring 2025-01-15-14.json to $REMOTE_HOST..."
  scp "$JSON_DATA" "$REMOTE_HOST":~/JSON-DATA/2025-01-15-14.json
else
  echo "2025-01-15-14.json already present on $REMOTE_HOST (1,039,410,676 bytes)."
fi

echo "=== [2/3] Executing setup and 4-way comparative benchmarks on $REMOTE_HOST ==="
ssh "$REMOTE_HOST" 'bash -s' << 'REMOTE_EOF'
set -euo pipefail

PG_PREFIX="$HOME/pg18"
PG_BIN="$PG_PREFIX/bin"
PG_DATA="$PG_PREFIX/data"
PORT=55432
export PATH="$PG_BIN:$HOME/.cargo/bin:$PATH"

if ! "$PG_BIN/pg_isready" -h /tmp -p "$PORT" >/dev/null 2>&1; then
  "$PG_BIN/pg_ctl" -D "$PG_DATA" -l "$PG_PREFIX/pg.log" -o "-p $PORT -k /tmp" start
fi

cd ~/bench_jsonschema
tar -xzf ~/bench_jsonschema/bundle.tar.gz

echo "--- Step 3.1: Ensuring LZ4 TOAST compression support ---"
if ! "$PG_BIN/pg_config" --configure | grep -q "\-\-with-lz4"; then
  if [ ! -f "$("$PG_BIN/pg_config" --pkglibdir)/pg_lz4_shim.so" ]; then
    cat << 'SHIM_EOF' > ~/bench_jsonschema/pg_lz4_shim.c
#include "postgres.h"
#include "fmgr.h"
#include "access/detoast.h"
#include "access/toast_compression.h"
#include "varatt.h"
#include <sys/mman.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>

extern int LZ4_versionNumber(void);
extern int LZ4_compressBound(int inputSize);
extern int LZ4_compress_default(const char *src, char *dst, int srcSize, int dstCapacity);
extern int LZ4_decompress_safe(const char *src, char *dst, int compressedSize, int dstCapacity);
extern int LZ4_decompress_safe_partial(const char *src, char *dst, int srcSize, int targetOutputSize, int dstCapacity);

PG_MODULE_MAGIC;

static struct varlena *real_lz4_compress_datum(const struct varlena *value) {
    int32 valsize = VARSIZE_ANY_EXHDR(value);
    int32 max_size = LZ4_compressBound(valsize);
    struct varlena *tmp = (struct varlena *) palloc(max_size + VARHDRSZ_COMPRESSED);
    int32 len = LZ4_compress_default(VARDATA_ANY(value), (char *) tmp + VARHDRSZ_COMPRESSED, valsize, max_size);
    if (len <= 0) elog(ERROR, "lz4 compression failed");
    if (len > valsize) { pfree(tmp); return NULL; }
    SET_VARSIZE_COMPRESSED(tmp, len + VARHDRSZ_COMPRESSED);
    return tmp;
}
static struct varlena *real_lz4_decompress_datum(const struct varlena *value) {
    struct varlena *result = (struct varlena *) palloc(VARDATA_COMPRESSED_GET_EXTSIZE(value) + VARHDRSZ);
    int32 rawsize = LZ4_decompress_safe((char *) value + VARHDRSZ_COMPRESSED, VARDATA(result), VARSIZE(value) - VARHDRSZ_COMPRESSED, VARDATA_COMPRESSED_GET_EXTSIZE(value));
    if (rawsize < 0) elog(ERROR, "compressed lz4 data is corrupt");
    SET_VARSIZE(result, rawsize + VARHDRSZ);
    return result;
}
static struct varlena *real_lz4_decompress_datum_slice(const struct varlena *value, int32 slicelength) {
    if (LZ4_versionNumber() < 10803) return real_lz4_decompress_datum(value);
    struct varlena *result = (struct varlena *) palloc(slicelength + VARHDRSZ);
    int32 rawsize = LZ4_decompress_safe_partial((char *) value + VARHDRSZ_COMPRESSED, VARDATA(result), VARSIZE(value) - VARHDRSZ_COMPRESSED, slicelength, slicelength);
    if (rawsize < 0) elog(ERROR, "compressed lz4 data is corrupt");
    SET_VARSIZE(result, rawsize + VARHDRSZ);
    return result;
}
static char real_CompressionNameToMethod(const char *compression) {
    if (strcmp(compression, "pglz") == 0) return TOAST_PGLZ_COMPRESSION;
    if (strcmp(compression, "lz4") == 0) return TOAST_LZ4_COMPRESSION;
    return InvalidCompressionMethod;
}
static void patch_jmp(void *target, void *replacement) {
    size_t pagesize = sysconf(_SC_PAGESIZE);
    uintptr_t page = ((uintptr_t) target) & ~(pagesize - 1);
    mprotect((void *) page, pagesize * 2, PROT_READ | PROT_WRITE | PROT_EXEC);
    unsigned char stub[12] = {0x48, 0xb8, 0,0,0,0,0,0,0,0, 0xff, 0xe0};
    uint64_t rep_addr = (uint64_t)(uintptr_t) replacement;
    memcpy(&stub[2], &rep_addr, 8);
    memcpy(target, stub, sizeof(stub));
    mprotect((void *) page, pagesize * 2, PROT_READ | PROT_EXEC);
}
void _PG_init(void) {
    patch_jmp((void *) lz4_compress_datum, (void *) real_lz4_compress_datum);
    patch_jmp((void *) lz4_decompress_datum, (void *) real_lz4_decompress_datum);
    patch_jmp((void *) lz4_decompress_datum_slice, (void *) real_lz4_decompress_datum_slice);
    patch_jmp((void *) CompressionNameToMethod, (void *) real_CompressionNameToMethod);
}
SHIM_EOF
    gcc -O2 -fPIC -shared -I"$("$PG_BIN/pg_config" --includedir-server)" ~/bench_jsonschema/pg_lz4_shim.c -o "$("$PG_BIN/pg_config" --pkglibdir)/pg_lz4_shim.so" /usr/lib/x86_64-linux-gnu/liblz4.so.1
  fi
  "$PG_BIN/psql" -X -h /tmp -p "$PORT" -d postgres -v ON_ERROR_STOP=1 \
    -c "ALTER SYSTEM SET session_preload_libraries = 'pg_lz4_shim';" \
    -c "SELECT pg_reload_conf();"
fi

echo "--- Step 3.2: Building & installing pl/js (if staged) and pl/jsonschema ---"
if [ -d ~/bench_jsonschema/pljs-patched ]; then
  cd ~/bench_jsonschema/pljs-patched
  make -C deps/quickjs clean
  rm -f src/*.o pljs.so
  make -C deps/quickjs -j$(nproc) libquickjs.a
  make PG_CONFIG="$PG_BIN/pg_config" -j$(nproc)
  make PG_CONFIG="$PG_BIN/pg_config" install
fi

cd ~/bench_jsonschema/pl-jsonschema
make PG_CONFIG="$PG_BIN/pg_config"
make PG_CONFIG="$PG_BIN/pg_config" install

echo "--- Step 3.3: Ensuring supabase/pg_jsonschema is installed ---"
if [ ! -f "$("$PG_BIN/pg_config" --pkglibdir)/pg_jsonschema.so" ]; then
  if [ ! -d ~/bench_jsonschema/pg_jsonschema ]; then
    git clone --depth 1 https://github.com/supabase/pg_jsonschema.git ~/bench_jsonschema/pg_jsonschema
  fi
  cd ~/bench_jsonschema/pg_jsonschema
  PGRX_VER="0.19.2"
  if ! cargo pgrx --version 2>/dev/null | grep -q "$PGRX_VER"; then
    cargo install --locked cargo-pgrx --version "$PGRX_VER"
  fi
  cargo pgrx init --pg18="$PG_BIN/pg_config"
  cargo pgrx install --pg-config="$PG_BIN/pg_config" --release
else
  echo "pg_jsonschema.so already installed in $($PG_BIN/pg_config --pkglibdir)"
fi

echo "--- Step 4: Ensuring jsondata database, public.jdata (251,755 rows), and jdata_type_idx ---"
if ! "$PG_BIN/psql" -X -h /tmp -p "$PORT" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'jsondata'" | grep -q 1; then
  "$PG_BIN/psql" -X -h /tmp -p "$PORT" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE jsondata;"
fi

"$PG_BIN/psql" -X -h /tmp -p "$PORT" -d jsondata -v ON_ERROR_STOP=1 << 'SQL_EOF'
CREATE EXTENSION IF NOT EXISTS plv8;
CREATE EXTENSION IF NOT EXISTS pljs;
CREATE EXTENSION IF NOT EXISTS pg_jsonschema;

CREATE TABLE IF NOT EXISTS public.jdata (
    id integer NOT NULL,
    data json
);
ALTER TABLE ONLY public.jdata ALTER COLUMN data SET COMPRESSION lz4;
CREATE SEQUENCE IF NOT EXISTS public.jdata_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.jdata_id_seq OWNED BY public.jdata.id;
ALTER TABLE ONLY public.jdata ALTER COLUMN id SET DEFAULT nextval('public.jdata_id_seq'::regclass);
SQL_EOF

python3 - << 'PY_EOF'
import json, os, subprocess, sys, time

PG_BIN = os.path.expanduser("~/pg18/bin")
PORT = "55432"
SCHEMAS_DIR = os.path.expanduser("~/bench_jsonschema/schemas")
JSON_FILE = os.path.expanduser("~/JSON-DATA/2025-01-15-14.json")

def run_psql(sql, db="jsondata", tuples_only=True):
    cmd = [f"{PG_BIN}/psql", "-X", "-h", "/tmp", "-p", PORT, "-d", db, "-v", "ON_ERROR_STOP=1"]
    if tuples_only:
        cmd.extend(["-t", "-A"])
    return subprocess.check_output(cmd, input=sql, text=True).strip()

cnt = int(run_psql("SELECT count(*) FROM public.jdata;") or "0")
if cnt != 251755:
    print(f"public.jdata has {cnt} rows; loading 251,755 rows from {JSON_FILE}...")
    run_psql("TRUNCATE public.jdata RESTART IDENTITY;")
    p = subprocess.Popen(
        [f"{PG_BIN}/psql", "-X", "-h", "/tmp", "-p", PORT, "-d", "jsondata", "-v", "ON_ERROR_STOP=1", "-c", "COPY public.jdata (data) FROM STDIN;"],
        stdin=subprocess.PIPE, text=True
    )
    with open(JSON_FILE, "r") as jf:
        for i, line in enumerate(jf, 1):
            line = line.rstrip("\r\n").replace("\\", "\\\\").replace("\t", "\\t")
            p.stdin.write(line + "\n")
    p.stdin.close()
    if p.wait() != 0:
        raise RuntimeError("COPY failed")
    run_psql("CREATE INDEX IF NOT EXISTS jdata_type_idx ON public.jdata USING btree ((data ->> 'type')); VACUUM ANALYZE public.jdata;")
else:
    run_psql("CREATE INDEX IF NOT EXISTS jdata_type_idx ON public.jdata USING btree ((data ->> 'type'));")

stats_line = run_psql("SELECT count(*), sum(length(data::text)), sum(pg_column_size(data)) FROM public.jdata;")
print("Table stats (count|raw_bytes|compressed_bytes):", stats_line)

events = [
    "CommitCommentEvent", "CreateEvent", "DeleteEvent", "ForkEvent", "GollumEvent",
    "IssueCommentEvent", "IssuesEvent", "MemberEvent", "PublicEvent", "PullRequestEvent",
    "PullRequestReviewCommentEvent", "PullRequestReviewEvent", "PushEvent", "ReleaseEvent", "WatchEvent"
]

class PsqlSession:
    def __init__(self):
        self.proc = subprocess.Popen(
            [f"{PG_BIN}/psql", "-X", "-q", "-h", "/tmp", "-p", PORT, "-d", "jsondata", "-v", "ON_ERROR_STOP=1", "-t", "-A"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1
        )
        self.exec_scalar("SET max_parallel_workers_per_gather = 0;")

    def exec_scalar(self, sql):
        marker = "__END_MARKER__"
        t0 = time.perf_counter()
        self.proc.stdin.write(f"{sql}\nSELECT '{marker}';\n")
        self.proc.stdin.flush()
        lines = []
        while True:
            line = self.proc.stdout.readline()
            if not line:
                err = self.proc.stderr.read()
                raise RuntimeError(f"psql session closed unexpectedly on SQL [{sql}]: {err}")
            s = line.rstrip("\r\n")
            if s == marker:
                break
            lines.append(s)
        dt_ms = (time.perf_counter() - t0) * 1000.0
        return (lines[0] if lines else ""), dt_ms

    def close(self):
        self.proc.stdin.close()
        self.proc.wait()

# ==============================================================================
# Pass 1: Benchmark pl/jsonschema on pl/js (QuickJS)
# ==============================================================================
print("--- Installing pl/jsonschema with engine = 'pljs' and registering 15 validators ---")
setup_pljs_sql = [
    "DROP EXTENSION IF EXISTS pl_jsonschema CASCADE;",
    "SET pl_jsonschema.engine = 'pljs';",
    "CREATE EXTENSION pl_jsonschema;"
]
for ev in events:
    with open(os.path.join(SCHEMAS_DIR, f"{ev}.schema.json")) as f:
        s = f.read().strip()
    fn = f"validate_{ev.lower()}"
    setup_pljs_sql.append(f"CREATE OR REPLACE FUNCTION public.{fn}(data json) RETURNS boolean LANGUAGE \"pl/jsonschema\" IMMUTABLE STRICT AS $s$\n{s}\n$s$;")
run_psql("\n".join(setup_pljs_sql))

handler_lang_pljs = run_psql("SELECT l.lanname FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang WHERE p.proname = 'pljsonschema_call_handler';")
print("Verified pljsonschema_call_handler engine for Pass 1:", handler_lang_pljs)
assert handler_lang_pljs == "pljs"

sess_pljs = PsqlSession()
pljs_metrics = {}
for ev in events:
    fn = f"validate_{ev.lower()}"
    sess_pljs.exec_scalar(f"SELECT count(length(data::text)) FROM public.jdata WHERE data ->> 'type' = '{ev}';")
    _, pljs_cold = sess_pljs.exec_scalar(f"SELECT count(public.{fn}(data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';")
    pljs_warm = []
    for _ in range(5):
        _, dt = sess_pljs.exec_scalar(f"SELECT count(public.{fn}(data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';")
        pljs_warm.append(dt)
    pljs_true_str, _ = sess_pljs.exec_scalar(f"SELECT count(*) FILTER (WHERE public.{fn}(data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';")
    pljs_metrics[ev] = {
        "pljs_true_rows": int(pljs_true_str),
        "pl_jsonschema_pljs_cold_ms": round(pljs_cold, 2),
        "pl_jsonschema_pljs_warm_med_ms": round(sorted(pljs_warm)[2], 2),
        "pl_jsonschema_pljs_warm_mean_ms": round(sum(pljs_warm) / len(pljs_warm), 2),
        "pl_jsonschema_pljs_warm_min_ms": round(min(pljs_warm), 2),
        "pl_jsonschema_pljs_warm_max_ms": round(max(pljs_warm), 2),
    }
    print(f"[pljs] {ev}: cold={pljs_metrics[ev]['pl_jsonschema_pljs_cold_ms']}ms warm_med={pljs_metrics[ev]['pl_jsonschema_pljs_warm_med_ms']}ms true={pljs_metrics[ev]['pljs_true_rows']}")
sess_pljs.close()

# ==============================================================================
# Pass 2: Benchmark pl/jsonschema on pl/v8 (V8) + supabase/pg_jsonschema (Compiled & Uncompiled)
# ==============================================================================
print("--- Installing pl/jsonschema with engine = 'plv8' and registering 15 validators ---")
setup_plv8_sql = [
    "DROP EXTENSION IF EXISTS pl_jsonschema CASCADE;",
    "SET pl_jsonschema.engine = 'plv8';",
    "CREATE EXTENSION pl_jsonschema;"
]
for ev in events:
    with open(os.path.join(SCHEMAS_DIR, f"{ev}.schema.json")) as f:
        s = f.read().strip()
    fn = f"validate_{ev.lower()}"
    setup_plv8_sql.append(f"CREATE OR REPLACE FUNCTION public.{fn}(data json) RETURNS boolean LANGUAGE \"pl/jsonschema\" IMMUTABLE STRICT AS $s$\n{s}\n$s$;")
run_psql("\n".join(setup_plv8_sql))

handler_lang_plv8 = run_psql("SELECT l.lanname FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang WHERE p.proname = 'pljsonschema_call_handler';")
print("Verified pljsonschema_call_handler engine for Pass 2:", handler_lang_plv8)
assert handler_lang_plv8 == "plv8"

sess = PsqlSession()
results = []
for ev in events:
    fn = f"validate_{ev.lower()}"
    with open(os.path.join(SCHEMAS_DIR, f"{ev}.schema.json")) as f:
        schema_txt = f.read().strip()

    st_str, _ = sess.exec_scalar(
        f"SELECT count(*) || '|' || sum(length(data::text)) || '|' || sum(pg_column_size(data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';"
    )
    row_cnt, raw_b, comp_b = [int(x) for x in st_str.split("|")]

    base_times = []
    for _ in range(3):
        _, dt = sess.exec_scalar(f"SELECT count(length(data::text)) FROM public.jdata WHERE data ->> 'type' = '{ev}';")
        base_times.append(dt)
    base_med = sorted(base_times)[1]

    # Mode A1: pl/jsonschema on plv8 (1st call = cold, next 5 = warm)
    _, pl_cold = sess.exec_scalar(f"SELECT count(public.{fn}(data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';")
    pl_warm = []
    for _ in range(5):
        _, dt = sess.exec_scalar(f"SELECT count(public.{fn}(data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';")
        pl_warm.append(dt)
    pl_true_str, _ = sess.exec_scalar(f"SELECT count(*) FILTER (WHERE public.{fn}(data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';")

    # Mode B: pg_jsonschema compiled (json_matches_compiled_schema)
    _, pgc_cold = sess.exec_scalar(
        f"SELECT count(public.json_matches_compiled_schema($s${schema_txt}$s$::json::jsonschema, data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';"
    )
    pgc_warm = []
    for _ in range(5):
        _, dt = sess.exec_scalar(
            f"SELECT count(public.json_matches_compiled_schema($s${schema_txt}$s$::json::jsonschema, data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';"
        )
        pgc_warm.append(dt)
    pgc_true_str, _ = sess.exec_scalar(
        f"SELECT count(*) FILTER (WHERE public.json_matches_compiled_schema($s${schema_txt}$s$::json::jsonschema, data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';"
    )

    # Mode C: pg_jsonschema uncompiled (json_matches_schema)
    _, sample_dt = sess.exec_scalar(
        f"SELECT count(public.json_matches_schema($s${schema_txt}$s$::json, data)) FROM (SELECT data FROM public.jdata WHERE data ->> 'type' = '{ev}' LIMIT 100) sub;"
    )
    est_full_ms = sample_dt * (row_cnt / min(row_cnt, 100))
    if est_full_ms <= 20000.0:
        _, pgu_ms = sess.exec_scalar(
            f"SELECT count(public.json_matches_schema($s${schema_txt}$s$::json, data)) FROM public.jdata WHERE data ->> 'type' = '{ev}';"
        )
        pgu_extrapolated = False
    else:
        _, sample500_dt = sess.exec_scalar(
            f"SELECT count(public.json_matches_schema($s${schema_txt}$s$::json, data)) FROM (SELECT data FROM public.jdata WHERE data ->> 'type' = '{ev}' LIMIT 500) sub;"
        )
        pgu_ms = sample500_dt * (row_cnt / 500.0)
        pgu_extrapolated = True

    rec = {
        "event_type": ev,
        "rows": row_cnt,
        "raw_bytes": raw_b,
        "compressed_bytes": comp_b,
        "schema_bytes": len(schema_txt.encode("utf-8")),
        "plv8_true_rows": int(pl_true_str),
        "pljs_true_rows": pljs_metrics[ev]["pljs_true_rows"],
        "pg_true_rows": int(pgc_true_str),
        "baseline_lz4_med_ms": round(base_med, 2),
        "pl_jsonschema_plv8_cold_ms": round(pl_cold, 2),
        "pl_jsonschema_plv8_warm_med_ms": round(sorted(pl_warm)[2], 2),
        "pl_jsonschema_plv8_warm_mean_ms": round(sum(pl_warm) / len(pl_warm), 2),
        "pl_jsonschema_plv8_warm_min_ms": round(min(pl_warm), 2),
        "pl_jsonschema_plv8_warm_max_ms": round(max(pl_warm), 2),
        "pl_jsonschema_pljs_cold_ms": pljs_metrics[ev]["pl_jsonschema_pljs_cold_ms"],
        "pl_jsonschema_pljs_warm_med_ms": pljs_metrics[ev]["pl_jsonschema_pljs_warm_med_ms"],
        "pl_jsonschema_pljs_warm_mean_ms": pljs_metrics[ev]["pl_jsonschema_pljs_warm_mean_ms"],
        "pl_jsonschema_pljs_warm_min_ms": pljs_metrics[ev]["pl_jsonschema_pljs_warm_min_ms"],
        "pl_jsonschema_pljs_warm_max_ms": pljs_metrics[ev]["pl_jsonschema_pljs_warm_max_ms"],
        "pg_jsonschema_compiled_cold_ms": round(pgc_cold, 2),
        "pg_jsonschema_compiled_med_ms": round(sorted(pgc_warm)[2], 2),
        "pg_jsonschema_compiled_mean_ms": round(sum(pgc_warm) / len(pgc_warm), 2),
        "pg_jsonschema_compiled_min_ms": round(min(pgc_warm), 2),
        "pg_jsonschema_compiled_max_ms": round(max(pgc_warm), 2),
        "pg_jsonschema_uncompiled_ms": round(pgu_ms, 2),
        "pg_jsonschema_uncompiled_extrapolated": pgu_extrapolated
    }
    print(json.dumps(rec))
    results.append(rec)

sess.close()

with open(os.path.expanduser("~/bench_jsonschema/dev02_results.json"), "w") as out:
    json.dump(results, out, indent=2)
PY_EOF
REMOTE_EOF

echo "=== [3/3] Fetching dev02_results.json ==="
scp "$REMOTE_HOST":~/bench_jsonschema/dev02_results.json "$OUT_DIR/dev02_results.json"
rm -f "$TARBALL"
echo "Done! Saved to $OUT_DIR/dev02_results.json"
