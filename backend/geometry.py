"""RoomPlan geometry ingestion: turn the iPad's CapturedRoom export into
human-readable measurements — most importantly doorway width vs walker width."""

from config import WALKER_WIDTH_IN

M_TO_IN = 39.3701


def ingest_roomplan(payload: dict) -> list[dict]:
    """Accepts the JSON the iPad posts after a room scan.

    Expected shape (produced by the app from CapturedRoom):
      {"room": "bathroom",
       "doors":    [{"width_m": 0.71}, ...],
       "openings": [{"width_m": 0.9}, ...],
       "floor_area_m2": 8.2}            # all fields optional
    Returns measurement dicts for state + report.
    """
    room = payload.get("room", "room")
    out: list[dict] = []

    for kind in ("doors", "openings"):
        for d in payload.get(kind) or []:
            w_m = d.get("width_m")
            if not w_m:
                continue
            w_in = round(w_m * M_TO_IN, 1)
            # RoomPlan labels big wall spans as "doors"; a real door is < ~60in
            if w_in > 60:
                out.append({"label": f"{room} wide opening", "room": room,
                            "kind": "span", "width_in": w_in,
                            "text": f"{w_in}in open span — not a doorway"})
                continue
            clears = w_in >= WALKER_WIDTH_IN + 1  # 1in margin for hands/knuckles
            label = f"{room} {kind[:-1]} width"
            if clears:
                text = (f"{w_in}in — clears Monica's {WALKER_WIDTH_IN:.0f}in walker")
            else:
                text = (f"{w_in}in — Monica's walker is {WALKER_WIDTH_IN:.0f}in wide; "
                        f"it will NOT fit through this {kind[:-1]}")
            out.append({"label": label, "room": room, "kind": kind[:-1],
                        "width_in": w_in, "walker_clears": clears, "text": text})

    area = payload.get("floor_area_m2")
    if area:
        out.append({"label": f"{room} floor area", "room": room, "kind": "area",
                    "text": f"{area:.1f} m² ({area * 10.764:.0f} sq ft)"})
    return out
