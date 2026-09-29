"""Private stdout transport for one nonce-bound Simulator test event.

Never prints subprocess output. The caller owns private storage and exports only
fixed report fields. A duplicate event never invokes its callback twice.
"""
import os
import queue
import signal
import subprocess
import threading
import time


class StreamFailure(Exception):
    def __init__(self, category):
        self.category = category


def run_with_one_event(argv, *, env, cwd, timeout, expected_line, on_event, partial,
                       output_limit=32 * 1024 * 1024):
    if (not isinstance(expected_line, bytes) or not expected_line.startswith(b'NIDAA_PICKER_MATCH_REQUEST:')
            or b'\n' in expected_line or timeout <= 0):
        raise StreamFailure('invalid_stream_parameters')
    started = time.monotonic()
    output = bytearray()
    pending = bytearray()
    events = 0
    foreign = False
    callback_failed = False
    late_event = False
    process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               env=env, cwd=cwd, start_new_session=True)
    packets = queue.Queue()
    def read_output():
        total = 0
        try:
            while True:
                chunk = os.read(process.stdout.fileno(), 4096)
                if not chunk:
                    break
                total += len(chunk)
                packets.put(chunk)
                if total > output_limit:
                    break
        except OSError:
            packets.put(False)
        finally:
            packets.put(None)
    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    reader_finished = False
    outcome = 'completed'
    try:
        while not reader_finished or process.poll() is None:
            remaining = timeout - (time.monotonic() - started)
            if remaining <= 0:
                raise StreamFailure('bounded_saved_test_timeout')
            try:
                packet = packets.get(timeout=min(0.2, remaining))
            except queue.Empty:
                continue
            if packet is None:
                reader_finished = True
                continue
            if packet is False:
                raise StreamFailure('private_output_read_failed')
            output.extend(packet)
            pending.extend(packet)
            if len(output) > output_limit:
                raise StreamFailure('private_output_size_limit')
            while b'\n' in pending:
                line, _, rest = pending.partition(b'\n')
                pending[:] = rest
                line = line.rstrip(b'\r')
                if not line.startswith(b'NIDAA_PICKER_MATCH_REQUEST:'):
                    continue
                if line != expected_line:
                    foreign = True
                    continue
                events += 1
                if events == 1:
                    if process.poll() is not None:
                        late_event = True
                        continue
                    try:
                        on_event(max(0, timeout - (time.monotonic() - started)))
                    except Exception:
                        # Preserve the original UI outcome. Do not repeat an
                        # action whose completion might now be uncertain.
                        callback_failed = True
        return subprocess.CompletedProcess(argv, process.returncode,
                                           output.decode('utf-8', errors='replace'), ''), {
            'exactEventCount': events, 'foreignEventObserved': foreign,
            'lateEventObserved': late_event,
            'callbackFailed': callback_failed, 'lineTerminated': not pending,
            'elapsedSeconds': round(time.monotonic() - started, 3)}
    except StreamFailure as error:
        outcome = error.category
        raise
    finally:
        if outcome != 'completed':
            # Only the process group created by this invocation is signalled.
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=3)
            except ProcessLookupError:
                pass
        if outcome != 'completed':
            partial(bytes(output), b'')
        reader.join(timeout=1)
        process.stdout.close()
