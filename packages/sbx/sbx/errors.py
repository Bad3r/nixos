# Copyright (c) 2026 Bad3r
"""The error sbx reports for a refused or failed request."""


class SbxError(Exception):
    """A request sbx refuses or cannot complete."""

    def __init__(
        self, message: str, *, code: str, details: dict[str, object] | None = None
    ) -> None:
        """Keep a stable error code, and fields for the JSON error object, next to the message."""
        super().__init__(message)
        self.code = code
        self.details = details or {}


def error_document(error: SbxError | OSError) -> dict[str, object]:
    """Return the JSON error object of a failed verb."""
    if isinstance(error, SbxError):
        return {"code": error.code, "message": str(error), **error.details}
    return {"code": "os-error", "message": str(error)}
