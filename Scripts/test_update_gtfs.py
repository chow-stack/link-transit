import io
import unittest
import zipfile

import update_gtfs


class GTFSConversionTests(unittest.TestCase):
    def make_archive(self, include_regular_calendar: bool = True) -> zipfile.ZipFile:
        files = {
            "routes.txt": (
                "route_id,route_short_name,route_long_name,route_color\n"
                "r1,1,Test Route,112233\n"
            ),
            "trips.txt": (
                "route_id,service_id,trip_id,shape_id,trip_headsign,direction_id,block_id\n"
                "r1,svc,t1,shape1,Downtown,0,\n"
            ),
            "shapes.txt": (
                "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\n"
                "shape1,39.1,-86.5,1\n"
            ),
            "stops.txt": (
                "stop_id,stop_name,stop_lat,stop_lon,location_type\n"
                "10,Test Stop,39.1,-86.5,0\n"
            ),
            "stop_times.txt": (
                "trip_id,arrival_time,departure_time,stop_id,stop_sequence\n"
                "t1,25:05:00,25:05:00,10,5\n"
            ),
            "calendar_dates.txt": "service_id,date,exception_type\nsvc,20260825,1\n",
        }
        if include_regular_calendar:
            files["calendar.txt"] = (
                "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n"
                "svc,1,1,1,1,1,0,0,20260101,20261231\n"
            )

        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for name, contents in files.items():
                archive.writestr(name, contents)
        buffer.seek(0)
        return zipfile.ZipFile(buffer)

    def test_preserves_stop_sequence_and_service_exceptions(self) -> None:
        with self.make_archive() as archive:
            resources = update_gtfs.convert(archive)

        self.assertEqual(
            resources["stop_times_optimized.json"]["t1"][0],
            {"s": 10, "a": "25:05:00", "q": 5},
        )
        self.assertEqual(
            resources["service_calendar.json"]["exceptions"][0],
            {"service_id": "svc", "date": "20260825", "exception_type": 1},
        )

    def test_accepts_calendar_dates_only_feed(self) -> None:
        with self.make_archive(include_regular_calendar=False) as archive:
            resources = update_gtfs.convert(archive)

        self.assertEqual(resources["service_calendar.json"]["calendars"], [])
        self.assertEqual(len(resources["service_calendar.json"]["exceptions"]), 1)


if __name__ == "__main__":
    unittest.main()
