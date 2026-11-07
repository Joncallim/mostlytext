"""Observe a live Darwin Unix peer; never send an application frame or retry a command."""
import ctypes
import os
from pathlib import Path
import socket
import stat
import sys

# Shipping Darwin sys/un.h, verified in the actual SDK. These are not Linux SO_PEERCRED.
SOL_LOCAL = 0
LOCAL_PEERPID = 0x002


def probe_endpoint(path: Path, expected_pid: int, timeout: float = 0.05):
    assert sys.platform == "darwin" and expected_pid > 0 and 0 < timeout <= 0.05
    result = {"ready": False}
    try:
        before = path.lstat()
        result.update(exists=True, mode=oct(stat.S_IMODE(before.st_mode)), uid=before.st_uid)
        if (not stat.S_ISSOCK(before.st_mode) or stat.S_IMODE(before.st_mode) != 0o600
                or before.st_uid != os.geteuid() or before.st_nlink != 1):
            result["refusal"] = "not-an-owned-private-socket"
            return result
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(timeout)
            connection.connect(str(path))
            libc = ctypes.CDLL(None, use_errno=True)
            libc.getpeereid.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)]
            libc.getpeereid.restype = ctypes.c_int
            libc.getsockopt.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                      ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint)]
            libc.getsockopt.restype = ctypes.c_int
            uid, gid = ctypes.c_uint(), ctypes.c_uint()
            pid = ctypes.c_int()
            size = ctypes.c_uint(ctypes.sizeof(pid))
            if libc.getpeereid(connection.fileno(), ctypes.byref(uid), ctypes.byref(gid)) != 0:
                raise OSError(ctypes.get_errno(), "getpeereid refused")
            if libc.getsockopt(connection.fileno(), SOL_LOCAL, LOCAL_PEERPID,
                               ctypes.byref(pid), ctypes.byref(size)) != 0:
                raise OSError(ctypes.get_errno(), "LOCAL_PEERPID refused")
            result.update(peer_uid=uid.value, peer_pid=pid.value)
            after = path.lstat()
            if (size.value != ctypes.sizeof(pid) or uid.value != os.geteuid() or pid.value != expected_pid
                    or (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino)):
                result["refusal"] = "peer-or-named-identity-mismatch"
                return result
            result["ready"] = True
            return result
    except OSError as error:
        result.update(exists=path.exists(), refusal=type(error).__name__, errno=error.errno)
        return result
