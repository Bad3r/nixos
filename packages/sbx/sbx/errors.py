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


def error_code(error: SbxError | OSError) -> str:
    """Return the stable code of a failure; an OSError is os-error."""
    return error.code if isinstance(error, SbxError) else "os-error"


def error_document(error: SbxError | OSError) -> dict[str, object]:
    """Return the JSON error object of a failed verb."""
    details = error.details if isinstance(error, SbxError) else {}
    return {"code": error_code(error), "message": str(error), **details}
