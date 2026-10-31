class ServiceError(Exception):
    """Any failure of the user service that is not 'the user does not exist'."""


class UserNotFound(ServiceError):
    """The requested user id has no record."""
