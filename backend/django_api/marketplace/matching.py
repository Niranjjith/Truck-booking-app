import math

from .models import Notification, Truck


def distance_km(first, second):
    try:
        lon1, lat1 = (float(value) for value in first["coordinates"])
        lon2, lat2 = (float(value) for value in second["coordinates"])
    except (KeyError, TypeError, ValueError):
        return None
    if not all(map(math.isfinite, (lon1, lat1, lon2, lat2))):
        return None
    if not (-180 <= lon1 <= 180 and -180 <= lon2 <= 180 and -90 <= lat1 <= 90 and -90 <= lat2 <= 90):
        return None
    lat_delta = math.radians(lat2 - lat1)
    lon_delta = math.radians(lon2 - lon1)
    haversine = (
        math.sin(lat_delta / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(lon_delta / 2) ** 2
    )
    return 6371.0088 * 2 * math.asin(math.sqrt(min(1.0, haversine)))


def matching_trucks(load, radius_km):
    pickup = load.pickup if isinstance(load.pickup, dict) else {}
    required_type = load.required_truck_type
    matches = []
    for truck in Truck.objects.filter(is_available=True, capacity_tons__gte=load.weight_tons).select_related("owner"):
        if required_type != "other" and truck.truck_type not in (required_type, "other"):
            continue
        location = truck.current_location or {}
        distance = distance_km(pickup, location)
        if distance is not None and distance <= radius_km:
            matches.append((truck, distance))
    return sorted(matches, key=lambda match: match[1])


def notify_truck_owners(load, radius_km):
    nearest_by_owner = {}
    for truck, distance in matching_trucks(load, radius_km):
        current = nearest_by_owner.get(truck.owner_id)
        if current is None or distance < current[1]:
            nearest_by_owner[truck.owner_id] = (truck, distance)
    notifications = []
    for truck, distance in nearest_by_owner.values():
        notifications.append(
            Notification(
                recipient=truck.owner,
                notification_type="nearby_load",
                title="A matching nearby load is available",
                message=f"{load.load_type} · {distance:.1f} km from pickup",
                payload={
                    "loadId": load.id,
                    "truckId": truck.id,
                    "distanceKm": round(distance, 2),
                },
            )
        )
    Notification.objects.bulk_create(notifications)
    return len(notifications)
