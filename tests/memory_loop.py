"""Optional socket-free loop for isolated ASGI tests in restricted Windows hosts.

Enabled only by AGRO_IN_MEMORY_TEST_LOOP=1. Runtime application code never
uses this loop, and it deliberately cannot register network sockets.
"""
import asyncio
import os
import selectors
import time


class MemorySelector(selectors.BaseSelector):
    def register(self, *args, **kwargs):
        raise RuntimeError("These isolated tests do not allow socket I/O")

    def unregister(self, *args, **kwargs):
        raise KeyError("No registered I/O")

    def select(self, timeout=None):
        time.sleep(min(0.005, max(0, timeout)) if timeout is not None else 0.005)
        return []

    def get_map(self):
        return {}


class MemoryLoop(asyncio.SelectorEventLoop):
    def __init__(self):
        super().__init__(selector=MemorySelector())

    def _make_self_pipe(self):
        self._ssock = self._csock = None

    def _close_self_pipe(self):
        pass

    def _write_to_self(self):
        pass


def backend_options():
    return {"loop_factory": MemoryLoop} if os.getenv("AGRO_IN_MEMORY_TEST_LOOP") == "1" else {}


def run_async(coroutine):
    if os.getenv("AGRO_IN_MEMORY_TEST_LOOP") == "1":
        with asyncio.Runner(loop_factory=MemoryLoop) as runner:
            return runner.run(coroutine)
    return asyncio.run(coroutine)
