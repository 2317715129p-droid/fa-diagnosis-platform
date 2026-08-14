"""Log data masking utilities."""

import re

_IPV4_PATTERN = re.compile(r"(?:[0-9]{1,3}\.){3}[0-9]{1,3}")
_SERIAL_PATTERN = re.compile(r"\b[A-Z0-9]{8,12}\b")
_USER_PATTERN = re.compile(r"user:\s*\w+")


def enforce_data_masking(raw_log: str) -> str:
    """Mask sensitive fields in a raw log string using ordered regex replacements.

    Replacements are applied in this order:

    1. IPv4 addresses -> ``10.0.0.X``
    2. Uppercase alphanumeric tokens (8-12 chars) -> ``SN_XXXXXX``
    3. ``user:<word>`` -> ``user:operator_X``

    Example:
        >>> raw = (
        ...     "192.168.1.10 disk SN=AB12CD34EF56 user:admin "
        ...     "connected from 10.20.30.40"
        ... )
        >>> enforce_data_masking(raw)
        '10.0.0.X disk SN=SN_XXXXXX user:operator_X connected from 10.0.0.X'

    Args:
        raw_log: Unmasked log text.

    Returns:
        Masked log text with sensitive values replaced.
    """
    masked = _IPV4_PATTERN.sub("10.0.0.X", raw_log)
    masked = _SERIAL_PATTERN.sub("SN_XXXXXX", masked)
    masked = _USER_PATTERN.sub("user:operator_X", masked)
    return masked
