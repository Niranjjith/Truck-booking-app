from rest_framework.views import exception_handler


def marketplace_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is None or not isinstance(response.data, dict) or "message" in response.data:
        return response
    detail = response.data.get("detail")
    if detail:
        response.data["message"] = str(detail)
    else:
        first_value = next(iter(response.data.values()), None)
        if isinstance(first_value, list) and first_value:
            response.data["message"] = str(first_value[0])
        elif isinstance(first_value, dict):
            nested_value = next(iter(first_value.values()), None)
            if isinstance(nested_value, list) and nested_value:
                response.data["message"] = str(nested_value[0])
            elif nested_value is not None:
                response.data["message"] = str(nested_value)
        elif first_value is not None:
            response.data["message"] = str(first_value)
    return response
