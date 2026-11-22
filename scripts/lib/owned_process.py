"""Run one command in its own POSIX process group and reap the whole group (macOS libproc).

run_owned(command, cwd=, env=, stdout=, timeout=) starts the command as a new session leader,
waits until it exits, times out or this process gets SIGINT/SIGTERM, then sends the group TERM
and KILL and waits until no member remains. It returns the command's status with how it ended,
and wrapperStatus 125 when the group could not be reaped or drained. Copied unchanged, apart from
this docstring, from ../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/owned_process.py,
the helper scripts/run-s2-full-v2.py used while it lived in the evidence folder.
"""
import ctypes
import errno
import os
import signal
import subprocess
import threading
import time

_libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
_libproc.proc_listpgrppids.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
_libproc.proc_listpgrppids.restype = ctypes.c_int
_unreaped = []


def _members(group):
    capacity = 64
    interruptions = 0
    while capacity <= 8192:
        values = (ctypes.c_int * capacity)()
        ctypes.set_errno(0)
        count = _libproc.proc_listpgrppids(group, values, ctypes.sizeof(values))
        code = ctypes.get_errno()
        if code == errno.EINTR:
            interruptions += 1
            if interruptions >= 3:
                raise InterruptedError(code, 'owned group observation was repeatedly interrupted')
            continue
        if count < 0 or code:
            raise OSError(code or errno.EIO, 'owned group membership query failed')
        if count < capacity:
            return {int(value) for value in values[:count] if value}
        capacity *= 2
    raise RuntimeError('owned group membership observation is incomplete')


def _terminal(pid):
    try:
        value = os.waitid(os.P_PID, pid, os.WEXITED | os.WNOWAIT | os.WNOHANG)
    except InterruptedError:
        return False
    return value is not None and value.si_code in (os.CLD_EXITED, os.CLD_KILLED, os.CLD_DUMPED)


def _signal_group(pid, number):
    if _terminal(pid) and _members(pid) <= {pid}:
        return
    os.killpg(pid, number)


def run_owned(command, *, cwd, env, stdout, timeout, grace=2, drain_timeout=5):
    wake = threading.Event()
    received_signal = None
    previous = {}
    process = None
    pinned = False
    cause = 'exited'
    command_status = None
    drained = False
    errors = []

    def interrupt(number, frame):
        nonlocal received_signal
        if received_signal is None:
            received_signal = number
        wake.set()

    def pause(deadline):
        wake.wait(min(0.02, max(0, deadline - time.monotonic())))
        wake.clear()

    try:
        if signal.getsignal(signal.SIGCHLD) == signal.SIG_IGN:
            raise RuntimeError('exclusive child wait ownership is unavailable')
        for number in (signal.SIGINT, signal.SIGTERM):
            previous[number] = signal.signal(number, interrupt)
        deadline = time.monotonic() + timeout
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        pinned = True
        while not _terminal(process.pid):
            if received_signal is not None:
                cause = 'interrupted'
                break
            if time.monotonic() >= deadline:
                cause = 'timeout'
                break
            pause(deadline)
    except ChildProcessError as error:
        pinned = False
        errors.append('exclusive child wait ownership lost ' + str(error))
    except BaseException as error:
        errors.append(type(error).__name__ + ' ' + str(error))
    finally:
        if process is not None and pinned:
            try:
                _signal_group(process.pid, signal.SIGTERM)
            except ChildProcessError as error:
                pinned = False
                errors.append('exclusive child wait ownership lost ' + str(error))
            except ProcessLookupError:
                pass
            except OSError as error:
                errors.append('owned group TERM failed ' + str(error))
            try:
                deadline = time.monotonic() + grace
                while True:
                    ended = _terminal(process.pid)
                    members = _members(process.pid)
                    if ended and members <= {process.pid}:
                        break
                    if time.monotonic() >= deadline:
                        break
                    pause(deadline)
            except ChildProcessError as error:
                pinned = False
                errors.append('exclusive child wait ownership lost ' + str(error))
            except BaseException as error:
                errors.append('owned group grace observation failed ' + str(error))
            if pinned:
                # WNOWAIT pins the leader identity through the final group signal.
                try:
                    _signal_group(process.pid, signal.SIGKILL)
                except ChildProcessError as error:
                    pinned = False
                    errors.append('exclusive child wait ownership lost ' + str(error))
                except ProcessLookupError:
                    pass
                except OSError as error:
                    errors.append('owned group KILL failed ' + str(error))
                if pinned:
                    try:
                        command_status = process.wait(timeout=drain_timeout)
                    except BaseException as error:
                        _unreaped.append(process)
                        errors.append('owned leader reap is unestablished ' + str(error))
        if process is not None:
            try:
                deadline = time.monotonic() + drain_timeout
                while _members(process.pid):
                    if time.monotonic() >= deadline:
                        raise RuntimeError('owned group drainage is unestablished')
                    pause(deadline)
                drained = True
            except BaseException as error:
                errors.append(str(error))
        for number, handler in previous.items():
            signal.signal(number, handler)
    if received_signal is not None:
        cause = 'interrupted'
    if errors or not drained or command_status is None:
        wrapper_status = 125
    elif cause == 'timeout':
        wrapper_status = 124
    elif cause == 'interrupted':
        wrapper_status = 128 + received_signal
    else:
        wrapper_status = command_status if command_status >= 0 else 128 - command_status
    return {'wrapperStatus': wrapper_status, 'commandStatus': command_status,
            'completion': cause, 'interruptSignal': received_signal,
            'groupDrained': drained, 'cleanupErrors': errors,
            'scope': 'owned_posix_process_group'}
