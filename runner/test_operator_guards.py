"""Guard against operator mistakes before any Docker or database mutation."""
import datetime
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import enable_host
import rehearse_host


class OperatorGuardsTest(unittest.TestCase):
    def test_live_database_name_is_rejected_before_docker(self):
        with patch("rehearse_host.command") as docker:
            for name in ("instantflow", "postgres", "instantflow_s08_bad;dropdb"):
                with self.assertRaises(ValueError):
                    rehearse_host.database_command("dropdb", name)
            docker.assert_not_called()

    def rejected_report(self, modify):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            image = "ghcr.io/iagobg/instantflow:" + "a" * 40
            runtime = "sha256:" + "b" * 64
            evidence = pathlib.Path(__file__).parents[1] / "docs/evidence"
            for name in ("isolation", "service", "application"):
                report = json.loads((evidence / ("sprint08-a1-" + name + ".json")).read_text())
                report["date"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                if name == "application":
                    report["release_image"] = image
                elif name == "isolation":
                    report["image"] = runtime
                modify(name, report)
                (root / (name + ".json")).write_text(json.dumps(report))

            def values(path):
                return {"INSTANTFLOW_IMAGE": image} if path.name == "instantflow.image.env" else {"PYTHON_IMAGE": runtime}

            with patch("enable_host.os.getuid", return_value=0), patch("enable_host.values", side_effect=values), patch("enable_host.subprocess.run") as docker:
                with self.assertRaises(ValueError):
                    enable_host.main(root, root / "fragment.yml", root)
                docker.assert_not_called()

    def test_wrong_release_acceptance_cannot_enable_live_execution(self):
        def change(name, report):
            if name == "application":
                report["release_image"] = "ghcr.io/iagobg/instantflow:" + "c" * 40
        self.rejected_report(change)

    def test_failed_host_check_cannot_enable_live_execution(self):
        def change(name, report):
            if name == "service":
                report["tests"][0]["passed"] = False
        self.rejected_report(change)

    def test_stale_acceptance_cannot_enable_live_execution(self):
        def change(name, report):
            if name == "isolation":
                report["date"] = "2000-01-01T00:00:00+00:00"
        self.rejected_report(change)
