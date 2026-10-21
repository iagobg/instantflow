"""Synthetic trip quotation. No approvals, reservations, payments or stage changes."""
def calculate(inputs):
    vehicles = (inputs["participants"] + inputs["capacity"] - 1) // inputs["capacity"]
    transport = vehicles * (inputs["base_cents"] + inputs["distance_km"] * inputs["rate_cents"])
    admission = inputs["participants"] * inputs["admission_cents"]
    total = transport + admission
    if total > 1_000_000_000:
        raise ValueError("quotation exceeds approved range")
    return {"vehicles": vehicles, "transport_cents": transport,
            "admission_cents": admission, "total_cents": total}
