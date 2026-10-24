import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"


class GoogleRoutesError(Exception):
    pass


def compute_route(origin, destination, api_key):
    payload = {
        "origin": {
            "location": {
                "latLng": {
                    "latitude": origin[1],
                    "longitude": origin[0],
                }
            }
        },
        "destination": {
            "location": {
                "latLng": {
                    "latitude": destination[1],
                    "longitude": destination[0],
                }
            }
        },
        "travelMode": "DRIVE",
        "routingPreference": "TRAFFIC_AWARE",
        "units": "METRIC",
    }
    request = Request(
        ROUTES_URL,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": api_key,
            "X-Goog-FieldMask": "routes.distanceMeters,routes.duration",
        },
    )
    try:
        with urlopen(request, timeout=10) as response:
            result = json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
        raise GoogleRoutesError("Google Maps could not calculate this route.") from error
    routes = result.get("routes")
    if not isinstance(routes, list) or not routes or not isinstance(routes[0], dict):
        raise GoogleRoutesError("Google Maps did not return a route for these locations.")
    route = routes[0]
    try:
        distance_meters = int(route["distanceMeters"])
        duration_seconds = int(str(route["duration"]).removesuffix("s"))
    except (KeyError, TypeError, ValueError) as error:
        raise GoogleRoutesError("Google Maps returned an invalid route estimate.") from error
    if distance_meters < 0 or duration_seconds < 0:
        raise GoogleRoutesError("Google Maps returned an invalid route estimate.")
    return {
        "distanceMeters": distance_meters,
        "durationSeconds": duration_seconds,
    }
