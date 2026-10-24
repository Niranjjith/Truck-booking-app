from celery import shared_task
from django.conf import settings
from django.db import transaction

from .matching import notify_truck_owners
from .models import Load


@shared_task
def notify_nearby_truck_owners(load_id):
    try:
        load = Load.objects.get(pk=load_id, status=Load.Status.SEARCHING)
    except Load.DoesNotExist:
        return 0
    return notify_truck_owners(load, settings.MATCHING_RADIUS_KM)


def schedule_load_notifications(load_id):
    if settings.REDIS_URL:
        transaction.on_commit(lambda: notify_nearby_truck_owners.delay(load_id))
        return
    notify_nearby_truck_owners(load_id)
