"""Only the trusted repository example is imported here; uploaded scripts require gVisor."""
import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / "priv" / "calculations" / "field_trip.py"
spec = importlib.util.spec_from_file_location("trip_example", path)
example = importlib.util.module_from_spec(spec)
spec.loader.exec_module(example)


class TripExampleTest(unittest.TestCase):
    def test_synthetic_quote_and_vehicle_capacity_boundary(self):
        inputs = {"participants": 81, "capacity": 40, "distance_km": 120,
                  "base_cents": 50000, "rate_cents": 250, "admission_cents": 2000}
        self.assertEqual(example.calculate(inputs), {
            "vehicles": 3, "transport_cents": 240000, "admission_cents": 162000, "total_cents": 402000})
        self.assertEqual(example.calculate({**inputs, "participants": 80})["vehicles"], 2)
        with self.assertRaises(ValueError):
            example.calculate({**inputs, "rate_cents": 100000, "distance_km": 2000,
                               "participants": 500, "capacity": 1})


if __name__ == "__main__":
    unittest.main()
