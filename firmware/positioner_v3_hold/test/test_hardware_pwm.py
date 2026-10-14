"""Mock serial safety checks for the hardware-capable PWM acceptance script."""
import pathlib
import tempfile
import unittest
from unittest.mock import patch
from firmware.positioner_v3_hold.test import hardware_pwm


class FakePort:
    def __init__(self,valid=True,config=True):
        self.valid=valid; self.config=config; self.hold=False; self.commands=[]
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def reset_input_buffer(self): pass
    def write(self,data): self.commands.append(data.decode().strip())
    def read_until(self,*args):
        command=self.commands[-1]
        if command=='HOLD OFF': self.hold=False; text='HOLD OFF OK'
        elif command=='HOLD ON': self.hold=True; text='HOLD ON OK'
        elif command=='PING': text='PONG'
        elif command=='TILT PWM CONFIG': text='TILT PWM CONFIG OK' if self.config else 'ERR: I2C_READ'
        elif command=='TILT PWM CHECK':
            text=(f'FW:V4.1_PWM_HOLD ENC_TILT_SOURCE:PWM PWM_CONFIG:1 HOLD:{int(self.hold)} '
                  f'RELEASES:1 ENC_TILT_VALID:{int(self.valid)} RAW_TILT:180.0 PWM_PERIOD_US:4351')
        else: raise AssertionError('Unexpected command '+command)
        return (text+'\nESP32-ANTENNA> ').encode()


class TestHardwarePWMSafety(unittest.TestCase):
    def run_fixture(self,port):
        with tempfile.TemporaryDirectory() as tmp, \
             patch.object(hardware_pwm,'__file__',str(pathlib.Path(tmp)/'firmware'/'positioner'/'test'/'hardware_pwm.py')), \
             patch('sys.argv',['hardware_pwm.py','--port','COM_TEST','--configure']), \
             patch.object(hardware_pwm.serial,'Serial',return_value=port), \
             patch.object(hardware_pwm.time,'sleep'):
            result=hardware_pwm.main()
        self.assertFalse(port.hold)
        self.assertEqual(port.commands[-1],'HOLD OFF')
        self.assertTrue(set(port.commands)<= {'HOLD OFF','HOLD ON','PING','TILT PWM CHECK','TILT PWM CONFIG'})
        return result
    def test_valid_pwm_acceptance_releases_without_motion(self):
        self.assertEqual(self.run_fixture(FakePort()),0)
    def test_missing_pwm_is_failure_not_success(self):
        self.assertEqual(self.run_fixture(FakePort(valid=False)),1)
    def test_failed_configuration_still_releases(self):
        self.assertEqual(self.run_fixture(FakePort(config=False)),1)


if __name__=='__main__': unittest.main()
