"""Rehearse old-schema forward migration and full multitenant backup restore in new disposable databases.

Uses operator credentials from MIGRATION_PGUSER/MIGRATION_PGPASSWORD and PostgreSQL binaries on PATH
(or PG_BIN). Never modifies or drops a serving database. Recovery databases are retained for inspection.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--backup", type=Path, help="Optional pre-01A custom-format backup")
args = parser.parse_args()
env = dict(os.environ)
env["PGUSER"] = env.get("MIGRATION_PGUSER", "postgres")
env["PGPASSWORD"] = env.get("MIGRATION_PGPASSWORD", "instantflow-local-only")
env.setdefault("PGHOST", "localhost")
env.setdefault("PGPORT", "55432")


def binary(name):
    return str(Path(env["PG_BIN"]) / name) if env.get("PG_BIN") else name


def run(command, extra_env=None):
    result = subprocess.run(command, cwd=ROOT, env={**env, **(extra_env or {})}, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{command[0]} failed: {result.stderr or result.stdout}")
    return result.stdout.strip()


def sql(database, statement):
    return run([binary("psql"), "-X", "-v", "ON_ERROR_STOP=1", "-qAt", "-d", database, "-c", statement])


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def snapshot(database, columns=None):
    if columns is None:
        columns = {}
        rows = sql(database, "SELECT table_name,column_name FROM information_schema.columns WHERE table_schema='public' AND table_name NOT IN ('schema_migrations') ORDER BY table_name,ordinal_position")
        for row in rows.splitlines():
            table, column = row.split("|")
            columns.setdefault(table, []).append(column)
    data = {}
    for table, names in columns.items():
        selected = ",".join('"' + name + '"' for name in names)
        data[table] = sql(database, f'SELECT row_to_json(row) FROM (SELECT {selected} FROM "{table}" ORDER BY id) row')
    return columns, data


suffix = uuid.uuid4().hex[:12]
original = "instantflow_rehearsal_old_" + suffix
restored = "instantflow_rehearsal_restore_" + suffix
sql("postgres", f"CREATE DATABASE {original} TEMPLATE template0 ENCODING 'UTF8'")
if args.backup:
    run([binary("pg_restore"), "--exit-on-error", "-d", original, str(args.backup.resolve())])
else:
    run(["mix", "ecto.migrate", "-r", "Instantflow.OperatorRepo", "--to", "20261020184948"], {"MIGRATION_DATABASE": original})
    definition = json.loads((ROOT / "priv/workflows/simple_approval.json").read_text())
    bindings = {"roles": {"requester": ["admin", "staff"], "reviewer": ["staff"]}, "departments": {"review_department": 1}}
    sql(original, f"""
    BEGIN;
    INSERT INTO organizations(id,name,timezone,inserted_at,updated_at) VALUES(1,'Escola Legada','America/Sao_Paulo',now(),now());
    INSERT INTO users(id,name,email,password_hash,active,inserted_at,updated_at) VALUES(1,'Pessoa fictícia','legacy@example.com','rehearsal-no-login',false,now(),now());
    INSERT INTO departments(id,organization_id,name,inserted_at,updated_at) VALUES(1,1,'Secretaria',now(),now());
    INSERT INTO memberships(organization_id,user_id,department_id,role,inserted_at,updated_at) VALUES(1,1,1,'admin',now(),now());
    INSERT INTO workflows(id,organization_id,key,name,inserted_at,updated_at) VALUES(1,1,'simple_approval','Aprovação',now(),now());
    INSERT INTO workflow_versions(id,workflow_id,number,definition,bindings,published_by_id,inserted_at,updated_at) VALUES(1,1,1,{literal(json.dumps(definition))}::jsonb,{literal(json.dumps(bindings))}::jsonb,1,now(),now());
    INSERT INTO tickets(id,organization_id,workflow_id,workflow_version_id,requester_id,assigned_department_id,stage,revision,inserted_at,updated_at) VALUES(1,1,1,1,1,1,'review',2,now(),now());
    INSERT INTO ticket_sections(ticket_id,key,values,revision,inserted_at,updated_at) VALUES(1,'request','{{"summary":"Preservar","justification":"Dado fictício"}}',2,now(),now());
    INSERT INTO transition_events(id,ticket_id,actor_id,operation,to_stage,revision,inserted_at,updated_at) VALUES(1,1,1,'create','draft',1,now(),now()),(2,1,1,'submit','review',2,now(),now());
    INSERT INTO command_receipts(actor_id,key,digest,ticket_id,result,inserted_at,updated_at) VALUES(1,'preserved-key',decode('001122','hex'),1,'{{"ticket_id":1,"revision":1}}',now(),now());
    INSERT INTO outbox_messages(ticket_id,event_id,key,kind,status,inserted_at,updated_at) VALUES(1,2,'preserved-pending','simulate_notification','pending',now(),now());
    COMMIT;
    """)
    # Explicit fixture IDs must leave sequences as ordinary legacy inserts would.
    # Never repair or rewrite sequences in a supplied backup.
    for table in ("organizations", "users", "departments", "workflows", "workflow_versions", "tickets", "transition_events"):
        sql(original, f"SELECT setval(pg_get_serial_sequence('{table}','id'), (SELECT max(id) FROM {table}), true)")

# The frozen column list compares every original value, including immutable payloads, IDs, pins and outcomes.
columns, before = snapshot(original)
if sql(original, "SELECT max(version) FROM schema_migrations") != "20261020184948":
    raise RuntimeError("Expected a pre-01A backup at Sprint 01")
run(["mix", "ecto.migrate", "-r", "Instantflow.OperatorRepo"], {"MIGRATION_DATABASE": original})
assert snapshot(original, columns)[1] == before, "Forward migration changed existing record content"
assert sql(original, "SELECT count(*) FROM outbox_messages WHERE organization_id IS NULL") == "0"
sql(original, "INSERT INTO organizations(slug,name,timezone,status,inserted_at,updated_at) VALUES('second-school','Segunda escola','America/Sao_Paulo','active',now(),now())")
sql(original, "INSERT INTO departments(organization_id,name,inserted_at,updated_at) SELECT id,'Secretaria',now(),now() FROM organizations WHERE slug='second-school'")
sql(original, "INSERT INTO membership_grants(organization_id,membership_id,department_id,role,inserted_at,updated_at) SELECT organization_id,id,department_id,'finance',now(),now() FROM memberships ORDER BY id LIMIT 1")
full_columns, full_before = snapshot(original)
backup = ROOT / ".local/backups" / ("rehearsed-multiorg-" + suffix + ".dump")
backup.parent.mkdir(parents=True, exist_ok=True)
run([binary("pg_dump"), "-Fc", "-d", original, "-f", str(backup)])
sql("postgres", f"CREATE DATABASE {restored} TEMPLATE template0 ENCODING 'UTF8'")
run([binary("pg_restore"), "--exit-on-error", "-d", restored, str(backup)])
assert snapshot(restored, full_columns)[1] == full_before, "Full restore did not preserve every tenant's rows"
# The current forward-only rollback must refuse without deleting the second school.
result = subprocess.run(["mix", "ecto.rollback", "-r", "Instantflow.OperatorRepo"], cwd=ROOT,
                        env={**env, "MIGRATION_DATABASE": restored}, capture_output=True, text=True)
assert result.returncode != 0 and "forward-only" in result.stdout + result.stderr
assert sql(restored, "SELECT count(*) FROM organizations") == "2"
print(json.dumps({"forward_preservation": "passed", "multitenant_restore": "passed", "rollback_refusal": "passed",
                  "migration_database": original, "restore_database": restored, "backup": str(backup)}, indent=2))
