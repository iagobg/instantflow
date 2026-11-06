"""Public campaign provenance; never serialize the private fixture's actors."""
from pathlib import Path

import benchmark_host as host

K6 = "grafana/k6@sha256:8663335c8c1c5a40dd51823ef980c584761a4a084a2297fca29a29ee495c6bc1"
WORKLOAD_SHA256 = "5b7aa7011e796b3794847052e2e94d7820143a96d5a4088456f0ca468990aba6"
ORIGIN_IP = "134.65.245.186"
SSH_HOST = "portfolio-server"


def workload_identity(path):
    host.require(path.is_file() and host.digest(path) == WORKLOAD_SHA256,
                 "Workload differs from the reviewed frozen school browser script")
    return {"name": "school-v1-browser", "sha256": WORKLOAD_SHA256,
            "fixture_source_commit": host.BASE_COMMIT}


def fixture_identity(path):
    fixture = host.read_json(path)
    host.require(fixture["fixture"] == "school-v1" and fixture["application_commit"] == host.BASE_COMMIT
                 and fixture["expected"] == {"organizations": 1, "workflows": 1, "cases": 12, "load_actors": 10},
                 "Private fixture belongs to a different baseline")
    actors = fixture["actors"]
    host.require(len(actors) == 10 and all(len({a[k] for a in actors}) == 10 for k in ["user_id", "email", "ticket_id"]),
                 "Fixture must contain ten distinct actors and records")
    return {"name": "school-v1", "source_commit": host.BASE_COMMIT,
            "source_image": host.BASE_IMAGE, "archive_sha256": host.BASE_HASH,
            "private_manifest_sha256": host.digest(path), "load_actors": 10, "initial_records": 12}


def manifest(application, ready, fixture, workload):
    host.validate_application(application)
    identity = ready["identity"]
    host.require(ready["status"] == "ready" and ready["application"] == application
                 and ready["frozen_fixture_restored"] is True
                 and identity["image"] == application["image"]
                 and identity["application_commit"] == application["application_commit"]
                 and identity["fixture_sha256"] == fixture["archive_sha256"] == host.BASE_HASH
                 and identity["database"] == host.DATABASE and identity["project"] == host.PROJECT
                 and identity["postgres_image"] == host.POSTGRES_IMAGE
                 and identity["pool_size"] == 10 and identity["endpoint_host"] == host.DOMAIN
                 and all(ready["inventory"]["table_counts"].get(k) == v for k, v in
                         {"organizations": 1, "workflows": 1, "tickets": 12}.items()),
                 "Prepared server differs from requested campaign arm or fixture")
    return {"schema": 1, "application": application, "fixture": fixture, "workload": workload,
            "operation_id": ready["operation_id"], "recovery_snapshot": ready["recovery_snapshot"],
            "initial_inventory": ready["inventory"], "target": "https://" + host.DOMAIN,
            "transport": {"origin_ip": ORIGIN_IP, "hostname": host.DOMAIN, "tls_verification": True},
            "resources": {"web_cpus": 2, "web_memory_bytes": 2_147_483_648,
                          "db_cpus": 1, "db_memory_bytes": 1_073_741_824, "pool_size": 10},
            "postgres_image": host.POSTGRES_IMAGE, "k6_image": K6,
            "postgres_metrics_settings": ready["metrics_settings"],
            "statement_statistics_available": ready["statement_statistics_available"],
            "host_controller_sha256": ready["controller_sha256"]}


def controller_hashes():
    folder = Path(__file__).resolve().parent
    names = ["benchmark_host.py", "benchmark_rollout.py", "benchmark_candidate.py",
             "benchmark_smoke.py", "benchmark_session.py", "benchmark_metrics.py", "benchmark_metrics_setup.py",
             "benchmark_provenance.py", "remote.py"]
    # In a checkout the compatibility wrapper retains its descriptive source name.
    if not (folder / "remote.py").exists():
        names[-1] = "benchmark_legacy.py"
    return {name: host.digest(folder / name) for name in names}
