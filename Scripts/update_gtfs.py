#!/usr/bin/env python3
"""Regenerate Link's bundled static JSON resources from a GTFS ZIP.

The app joins GTFS-Realtime vehicles to static trips by exact trip_id, so all
generated resources must come from the same GTFS snapshot.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import sys
import tempfile
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path


DEFAULT_GTFS_URL = (
    "https://s3.amazonaws.com/etatransit.gtfs/"
    "bloomingtontransit.etaspot.net/gtfs.zip"
)
WEEKDAYS = (
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
)
REQUIRED_FILES = {
    "routes.txt",
    "trips.txt",
    "shapes.txt",
    "stops.txt",
    "stop_times.txt",
}


def parse_args() -> argparse.Namespace:
    repository_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--zip", type=Path, help="Use an existing GTFS ZIP")
    source.add_argument("--url", default=DEFAULT_GTFS_URL, help="GTFS ZIP URL")
    parser.add_argument(
        "--output",
        type=Path,
        default=repository_root / "link" / "Resources" / "StaticData",
        help="StaticData output directory",
    )
    return parser.parse_args()


def read_source(args: argparse.Namespace) -> bytes:
    if args.zip:
        return args.zip.read_bytes()

    request = urllib.request.Request(
        args.url,
        headers={"User-Agent": "Link-GTFS-Updater/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def read_table(archive: zipfile.ZipFile, filename: str) -> list[dict[str, str]]:
    with archive.open(filename) as raw_file:
        text_file = io.TextIOWrapper(raw_file, encoding="utf-8-sig", newline="")
        return list(csv.DictReader(text_file))


def required(row: dict[str, str], key: str, source: str) -> str:
    value = (row.get(key) or "").strip()
    if not value:
        raise ValueError(f"{source}: missing required {key}")
    return value


def optional_int(value: str | None) -> int | None:
    value = (value or "").strip()
    return int(value) if value else None


def time_to_minutes(value: str) -> int:
    parts = value.split(":")
    if len(parts) != 3:
        raise ValueError(f"Invalid GTFS time: {value}")
    hour, minute, second = (int(part) for part in parts)
    return hour * 60 + minute + (1 if second >= 30 else 0)


def minutes_to_time(value: int) -> str:
    hour, minute = divmod(value, 60)
    return f"{hour:02d}:{minute:02d}"


def convert(archive: zipfile.ZipFile) -> dict[str, object]:
    archive_files = set(archive.namelist())
    missing = REQUIRED_FILES - archive_files
    if missing:
        raise ValueError(f"GTFS ZIP is missing: {', '.join(sorted(missing))}")
    if not {"calendar.txt", "calendar_dates.txt"}.intersection(archive_files):
        raise ValueError("GTFS ZIP must include calendar.txt or calendar_dates.txt")

    route_rows = read_table(archive, "routes.txt")
    trip_rows = read_table(archive, "trips.txt")
    shape_rows = read_table(archive, "shapes.txt")
    stop_rows = read_table(archive, "stops.txt")
    stop_time_rows = read_table(archive, "stop_times.txt")
    calendar_rows = (
        read_table(archive, "calendar.txt") if "calendar.txt" in archive_files else []
    )
    calendar_date_rows = (
        read_table(archive, "calendar_dates.txt")
        if "calendar_dates.txt" in archive_files
        else []
    )

    routes = [
        {
            "route_id": required(row, "route_id", "routes.txt"),
            "route_short_name": required(row, "route_short_name", "routes.txt"),
            "route_long_name": required(row, "route_long_name", "routes.txt"),
            "route_color": (row.get("route_color") or "").strip() or None,
        }
        for row in route_rows
    ]

    trips = [
        {
            "route_id": required(row, "route_id", "trips.txt"),
            "service_id": required(row, "service_id", "trips.txt"),
            "trip_id": required(row, "trip_id", "trips.txt"),
            "shape_id": (row.get("shape_id") or "").strip() or None,
            "trip_headsign": (row.get("trip_headsign") or "").strip(),
            "direction_id": optional_int(row.get("direction_id")),
            "block_id": (row.get("block_id") or "").strip() or None,
        }
        for row in trip_rows
    ]

    shapes = [
        {
            "shape_id": required(row, "shape_id", "shapes.txt"),
            "shape_pt_lat": float(required(row, "shape_pt_lat", "shapes.txt")),
            "shape_pt_lon": float(required(row, "shape_pt_lon", "shapes.txt")),
            "shape_pt_sequence": int(
                required(row, "shape_pt_sequence", "shapes.txt")
            ),
        }
        for row in shape_rows
    ]
    shapes.sort(key=lambda row: (row["shape_id"], row["shape_pt_sequence"]))

    stops = [
        {
            "id": int(required(row, "stop_id", "stops.txt")),
            "name": required(row, "stop_name", "stops.txt"),
            "lat": float(required(row, "stop_lat", "stops.txt")),
            "lon": float(required(row, "stop_lon", "stops.txt")),
        }
        for row in stop_rows
        if (row.get("location_type") or "0").strip() in {"", "0"}
    ]
    stops.sort(key=lambda row: row["id"])

    ordered_stop_times: dict[str, list[tuple[int, dict[str, object]]]] = defaultdict(list)
    trip_time_bounds: dict[str, tuple[int, int]] = {}
    for row in stop_time_rows:
        trip_id = required(row, "trip_id", "stop_times.txt")
        arrival_time = required(row, "arrival_time", "stop_times.txt")
        sequence = int(required(row, "stop_sequence", "stop_times.txt"))
        ordered_stop_times[trip_id].append(
            (
                sequence,
                {
                    "s": int(required(row, "stop_id", "stop_times.txt")),
                    "a": arrival_time,
                    "q": sequence,
                },
            )
        )
        minutes = time_to_minutes(arrival_time)
        if trip_id in trip_time_bounds:
            current_start, current_end = trip_time_bounds[trip_id]
            trip_time_bounds[trip_id] = (
                min(current_start, minutes),
                max(current_end, minutes),
            )
        else:
            trip_time_bounds[trip_id] = (minutes, minutes)

    stop_times = {
        trip_id: [entry for _, entry in sorted(entries, key=lambda item: item[0])]
        for trip_id, entries in sorted(ordered_stop_times.items())
    }

    active_weekdays_by_service: dict[str, set[str]] = defaultdict(set)
    for row in calendar_rows:
        service_id = required(row, "service_id", "calendar.txt")
        for weekday in WEEKDAYS:
            if (row.get(weekday) or "0").strip() == "1":
                active_weekdays_by_service[service_id].add(weekday)

    route_hours: dict[str, dict[str, list[int]]] = defaultdict(dict)
    for trip in trips:
        bounds = trip_time_bounds.get(trip["trip_id"])
        if bounds is None:
            continue
        route_id = str(trip["route_id"])
        service_id = str(trip["service_id"])
        for weekday in active_weekdays_by_service.get(service_id, set()):
            if weekday in route_hours[route_id]:
                current = route_hours[route_id][weekday]
                current[0] = min(current[0], bounds[0])
                current[1] = max(current[1], bounds[1])
            else:
                route_hours[route_id][weekday] = [bounds[0], bounds[1]]

    route_service_hours = []
    for route in routes:
        route_id = route["route_id"]
        weekday_hours = route_hours.get(route_id, {})
        route_service_hours.append(
            {
                "route_id": route_id,
                "service_hours": {
                    weekday: (
                        {
                            "start": minutes_to_time(weekday_hours[weekday][0]),
                            "end": minutes_to_time(weekday_hours[weekday][1]),
                        }
                        if weekday in weekday_hours
                        else None
                    )
                    for weekday in WEEKDAYS
                },
            }
        )

    service_calendar = {
        "calendars": [
            {
                "service_id": required(row, "service_id", "calendar.txt"),
                **{
                    weekday: (row.get(weekday) or "0").strip() == "1"
                    for weekday in WEEKDAYS
                },
                "start_date": required(row, "start_date", "calendar.txt"),
                "end_date": required(row, "end_date", "calendar.txt"),
            }
            for row in calendar_rows
        ],
        "exceptions": [
            {
                "service_id": required(
                    row, "service_id", "calendar_dates.txt"
                ),
                "date": required(row, "date", "calendar_dates.txt"),
                "exception_type": int(
                    required(row, "exception_type", "calendar_dates.txt")
                ),
            }
            for row in calendar_date_rows
        ],
    }

    resources: dict[str, object] = {
        "routes.json": routes,
        "trips.json": trips,
        "shapes.json": shapes,
        "stops_optimized.json": stops,
        "stop_times_optimized.json": stop_times,
        "route_service_hours.json": route_service_hours,
        "service_calendar.json": service_calendar,
    }
    validate(resources)
    return resources


def validate(resources: dict[str, object]) -> None:
    routes = resources["routes.json"]
    trips = resources["trips.json"]
    shapes = resources["shapes.json"]
    stops = resources["stops_optimized.json"]
    stop_times = resources["stop_times_optimized.json"]
    service_calendar = resources["service_calendar.json"]

    route_ids = {row["route_id"] for row in routes}
    trip_ids = {row["trip_id"] for row in trips}
    shape_ids = {row["shape_id"] for row in shapes}
    stop_ids = {row["id"] for row in stops}

    if len(route_ids) != len(routes):
        raise ValueError("Duplicate route_id values")
    if len(trip_ids) != len(trips):
        raise ValueError("Duplicate trip_id values")

    service_ids = {
        row["service_id"] for row in service_calendar["calendars"]
    }
    service_ids.update(
        row["service_id"] for row in service_calendar["exceptions"]
    )

    unknown_trip_routes = {row["route_id"] for row in trips} - route_ids
    unknown_trip_shapes = {
        row["shape_id"] for row in trips if row["shape_id"] is not None
    } - shape_ids
    trips_without_stop_times = trip_ids - set(stop_times)
    unknown_stop_time_trips = set(stop_times) - trip_ids
    unknown_stop_ids = {
        entry["s"] for entries in stop_times.values() for entry in entries
    } - stop_ids

    failures = {
        "trip route IDs": unknown_trip_routes,
        "trip shape IDs": unknown_trip_shapes,
        "trips without stop times": trips_without_stop_times,
        "stop-time trip IDs": unknown_stop_time_trips,
        "stop-time stop IDs": unknown_stop_ids,
        "trip service IDs": {row["service_id"] for row in trips} - service_ids,
    }
    messages = [
        f"Unknown {label}: {sorted(values)[:10]}"
        for label, values in failures.items()
        if values
    ]
    if messages:
        raise ValueError("\n".join(messages))

    if not all(38.5 <= row["lat"] <= 40.0 and -88.0 <= row["lon"] <= -85.0 for row in stops):
        raise ValueError("One or more stops have coordinates outside the Bloomington region")


def write_resources(resources: dict[str, object], output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="link-gtfs-") as temp_directory:
        temp_path = Path(temp_directory)
        for filename, payload in resources.items():
            destination = temp_path / filename
            destination.write_text(
                json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
        for filename in resources:
            (temp_path / filename).replace(output / filename)


def main() -> int:
    args = parse_args()
    try:
        source = read_source(args)
        with zipfile.ZipFile(io.BytesIO(source)) as archive:
            resources = convert(archive)
        write_resources(resources, args.output)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"GTFS update failed: {error}", file=sys.stderr)
        return 1

    routes = resources["routes.json"]
    trips = resources["trips.json"]
    stops = resources["stops_optimized.json"]
    stop_times = resources["stop_times_optimized.json"]
    print(
        "Updated static GTFS: "
        f"{len(routes)} routes, {len(trips)} trips, {len(stops)} stops, "
        f"{len(stop_times)} stop-time trip entries"
    )
    print(f"Output: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
