#!/usr/bin/env python3
"""Fine-grained access control in BigQuery. Idempotent.

Column level: taxonomy "datos-personales" (Data Catalog, location us) with two policy tags:
  identificador_usuario  -> events_raw.user_id
  identificador_cliente  -> olist_customers.customer_unique_id
Only FULL_READERS (Fine-Grained Reader) can select those columns; anyone else gets "access denied" on them
and must leave them out (the rest of the table stays readable). Dynamic masking (data policies with SHA-256
or a masking routine) needs the project to belong to a Google Cloud organization; this project has none.
Row level: sql/15_acceso_filas.sql (row access policies on fact_pedidos).

Usage: python3 infra/06_acceso_fino.py   (needs Policy Tag Admin + Data Policy Admin, i.e. project owner)
"""
import json
import os
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_config():
    cfg = {}
    for line in open(os.path.join(ROOT, "config.env")):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            cfg[k] = v
    return cfg


CFG = load_config()
P, LOC, DS = CFG["PROJECT_ID"], "us", CFG["DATASET"]
# sa-transform reads user_id because the daily stream deduplication (sql/17) compares whole rows
FULL_READERS = [f"user:{CFG['OWNER_ACCOUNT']}", f"user:{CFG['TEAM_FULL_ACCESS']}",
                f"serviceAccount:{CFG['SA_TRANSFORM']}"]
TOKEN = subprocess.run(["gcloud", "auth", "print-access-token"], capture_output=True, text=True,
                       check=True).stdout.strip()


# Python >= 3.13 enables strict X.509 checks, which reject the office firewall's CA (no Authority Key
# Identifier). Certificates are still verified; only the strict flag is dropped.
SSL_CTX = ssl.create_default_context()
SSL_CTX.verify_flags &= ~ssl.VERIFY_X509_STRICT


def api(method, url, body=None):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json",
                                          "x-goog-user-project": P})
    try:
        with urllib.request.urlopen(req, context=SSL_CTX) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        sys.exit(f"{method} {url} -> {e.code} {e.read().decode()[:500]}")


DC =f"https://datacatalog.googleapis.com/v1/projects/{P}/locations/{LOC}"

# 1. Taxonomy with fine-grained access control turned on
tax = next((t for t in (api("GET", f"{DC}/taxonomies") or {}).get("taxonomies", [])
            if t["displayName"] == "datos-personales"), None)
if not tax:
    tax = api("POST", f"{DC}/taxonomies", {
        "displayName": "datos-personales",
        "description": "Identificadores de personas (glosario: Dato personal).",
        "activatedPolicyTypes": ["FINE_GRAINED_ACCESS_CONTROL"]})
print("taxonomy", tax["name"])

# 2. Policy tags
existing = {t["displayName"]: t for t in (api("GET", f"https://datacatalog.googleapis.com/v1/{tax['name']}/policyTags")
                                         or {}).get("policyTags", [])}
tags = {}
for name, desc in [("identificador_usuario", "user_id de REES46"),
                   ("identificador_cliente", "customer_unique_id de Olist")]:
    tags[name] = existing.get(name) or api("POST", f"https://datacatalog.googleapis.com/v1/{tax['name']}/policyTags",
                                           {"displayName": name, "description": desc})
    print("policy tag", name, tags[name]["name"])

# 3. Who sees the real value
for t in tags.values():
    api("POST", f"https://datacatalog.googleapis.com/v1/{t['name']}:setIamPolicy", {"policy": {"bindings": [
        {"role": "roles/datacatalog.categoryFineGrainedReader", "members": FULL_READERS}]}})

# 4. Attach the tags to the columns
for table, column, tag in [("events_raw", "user_id", "identificador_usuario"),
                           ("olist_customers", "customer_unique_id", "identificador_cliente")]:
    ref = f"{P}:{DS}.{table}"
    schema = json.loads(subprocess.run(["bq", "show", "--schema", "--format=json", ref], capture_output=True,
                                       text=True, check=True).stdout)
    for f in schema:
        if f["name"] == column:
            f["policyTags"] = {"names": [tags[tag]["name"]]}
    with tempfile.NamedTemporaryFile("w", suffix=".json") as tmp:
        json.dump(schema, tmp)
        tmp.flush()
        subprocess.run(["bq", "update", ref, tmp.name], check=True, capture_output=True)
    print("tagged", f"{table}.{column}", "->", tag)

print("Acceso fino OK. Filas: sql/run.sh sql/15_acceso_filas.sql")
