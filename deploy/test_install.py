import pathlib
import tempfile
import unittest

from install import install


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        for name in ("compose.yml", "Caddyfile", ".env"):
            (self.root / name).write_text("existing shared configuration\n")

    def test_generates_matching_private_credentials_and_preserves_them_on_rerun(self):
        install(self.root)
        runtime = (self.root / "instantflow.env").read_text()
        operator = (self.root / "instantflow.operator.env").read_text()
        database = (self.root / "instantflow.db.env").read_text()
        self.assertNotIn("REPLACE_", runtime + operator + database)
        password = next(line.split("=", 1)[1] for line in operator.splitlines()
                        if line.startswith("RUNTIME_DB_PASSWORD="))
        self.assertIn(":" + password + "@", runtime)
        db_password = next(line.split("=", 1)[1] for line in database.splitlines()
                           if line.startswith("POSTGRES_PASSWORD="))
        self.assertIn(":" + db_password + "@", operator)
        install(self.root)
        self.assertEqual(runtime, (self.root / "instantflow.env").read_text())
        self.assertEqual(operator, (self.root / "instantflow.operator.env").read_text())
        for name in ("instantflow.env", "instantflow.operator.env", "instantflow.db.env"):
            self.assertEqual((self.root / name).stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.root / ".env").read_text(), "existing shared configuration\n")

    def test_refuses_partial_credentials(self):
        (self.root / "instantflow.env").write_text("existing secret\n")
        with self.assertRaisesRegex(ValueError, "Partial"):
            install(self.root)
        self.assertFalse((self.root / "instantflow.db.env").exists())

    def test_refuses_conflicting_configuration(self):
        (self.root / "projects").mkdir()
        (self.root / "projects/instantflow.compose.yml").write_text("custom\n")
        with self.assertRaisesRegex(ValueError, "differs"):
            install(self.root)
        self.assertFalse((self.root / "instantflow.env").exists())


if __name__ == "__main__":
    unittest.main()
