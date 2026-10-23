"""Patch the Python boundary for MATLAB controller tests; never opens serial."""
import json
from unittest.mock import patch
from python import nanovna_bridge as bridge


class TerminalJobPatch:
    def __init__(self, state, code):
        identity = dict(device_variant=2, protocol_version=1, hardware_revision=2,
                        firmware_major=1, firmware_minor=2, port='FAKE',
                        is_v2=True, status='OK')
        job = dict(job_id='terminal-fixture', generation=1, state=state)
        if code:
            job['error'] = dict(code=code, message='Injected transport loss')
        self.patches = [
            patch.object(bridge, 'connect', return_value='CONNECTED:FAKE'),
            patch.object(bridge, 'identify', return_value=identity),
            patch.object(bridge, 'disconnect', return_value='DISCONNECTED'),
            patch.object(bridge, 'start_sweep_json', return_value=json.dumps(
                dict(status='OK', payload=dict(job_id='terminal-fixture')))),
            patch.object(bridge, 'poll_sweep_json', return_value=json.dumps(
                dict(status='OK', payload=job))),
        ]
        for item in self.patches:
            item.start()

    def close(self):
        for item in reversed(self.patches):
            item.stop()
