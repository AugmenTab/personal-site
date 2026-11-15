"""Shared helpers for the development art tools."""

import os


def chown_like_work(*paths: str) -> None:
    """Give generated files to whoever owns the bind-mounted repo.

    The tools container runs as root; on Linux hosts that would leave
    root-owned files in the working tree. Docker Desktop translates ownership,
    so this is a no-op there in practice.
    """
    st = os.stat("/work")
    for path in paths:
        try:
            os.chown(path, st.st_uid, st.st_gid)
        except PermissionError:
            pass
