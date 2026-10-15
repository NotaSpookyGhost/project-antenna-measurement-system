"""Matched stationary Tilt comparison; always restore the current PWM build.

Physical condition reported by user: 1 m cable, no external SDA pull-up,
OUT -> GPIO23, SDA/SCL retained. No STEP/GOTO/ZERO or OTP commands.
The I2C sample script is copied unchanged from the prior 30/100/30 trial.
"""
import datetime
import json
import pathlib
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PIO = pathlib.Path.home() / '.platformio/penv/Scripts/platformio.exe'
report = {
    'started': datetime.datetime.now().isoformat(),
    'physical_condition': {'tilt_cable_m': 1, 'sda_pullup_ohm': None,
                           'out_gpio': 23, 'sda_scl_retained': True},
    'no_commanded_motion': True,
    'pwm_restored': False,
}


def run(name, args):
    print('START ' + name, flush=True)
    with (HERE / (name + '.log')).open('w', encoding='utf-8') as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log,
                                stderr=subprocess.STDOUT, timeout=180)
    report[name + '_exit'] = result.returncode
    print('END ' + name + ': exit ' + str(result.returncode), flush=True)
    if result.returncode:
        print((HERE / (name + '.log')).read_text(encoding='utf-8')[-2000:], flush=True)
        raise RuntimeError(name + ' failed')


def upload(env, name):
    run(name, [str(PIO), 'run', '-d', 'firmware/positioner_v3_hold',
               '-e', env, '-t', 'upload'])


def qualify_i2c():
    phases = json.loads((HERE / 'summary.json').read_text(encoding='utf-8'))
    raw = (HERE / 'stationary.log').read_text(encoding='utf-8')
    texts = re.findall(r'PAN:.*?FW:V4\.0_HOLD[^\r\n]*', raw)
    offset = 0
    for phase in phases:
        angles = []
        for text in texts[offset:offset + phase['reads']]:
            if re.search(r'ENC_TILT_VALID:1\b', text):
                angles.append(float(re.search(r'RAW_TILT:\s*([^\s]+)', text)[1]))
        offset += phase['reads']
        relative = [(a - angles[0] + 180) % 360 - 180 for a in angles]
        phase['circular_span_deg'] = max(relative) - min(relative) if relative else None
        phase['tilt_passed'] = (
            len(angles) == phase['reads'] and
            phase['tilt_valid'] == phase['reads'] and
            phase['circular_span_deg'] <= 2 and
            phase['release_counter_start'] == phase['release_counter_end'])
    report['i2c_phases'] = phases
    report['i2c_passed'] = (len(phases) == 3 and
                           [p['reads'] for p in phases] == [30, 100, 30] and
                           all(p['tilt_passed'] for p in phases))
    print(json.dumps({'i2c_passed': report['i2c_passed'], 'phases': phases}), flush=True)


try:
    shutil.copyfile(ROOT / 'data/validation/tilt_pwm_20261014_164042/probe_loaded_pwm.py',
                    HERE / 'probe_loaded_pwm.py')
    run('initial_pwm_probe', [sys.executable, '-X', 'utf8', str(HERE / 'probe_loaded_pwm.py')])
    report['initial_pwm_probe'] = (HERE / 'loaded_probe.log').read_text(encoding='utf-8')
    upload('esp32doit-devkit-v1', 'i2c_upload')
    run('i2c_stationary', [sys.executable, '-X', 'utf8', str(HERE / 'stationary_check.py')])
    qualify_i2c()
except Exception as exc:
    report['experiment_error'] = str(exc)
    print('EXPERIMENT ERROR: ' + str(exc), flush=True)
finally:
    try:
        upload('tilt-pwm', 'pwm_restore_upload')
        run('restored_pwm_acceptance', [sys.executable, '-X', 'utf8',
            'firmware/positioner_v3_hold/test/hardware_pwm.py', '--port', 'COM5', '--configure'])
        log = (HERE / 'restored_pwm_acceptance.log').read_text(encoding='utf-8')
        match = re.search(r'PASS Tilt PWM stationary acceptance; (.+)', log)
        if not match:
            raise RuntimeError('No passing PWM report location')
        pwm_folder = pathlib.Path(match[1].strip())
        report['restored_pwm_folder'] = str(pwm_folder)
        report['restored_pwm'] = json.loads((pwm_folder / 'summary.json').read_text(encoding='utf-8'))
        report['pwm_restored'] = report['restored_pwm']['passed'] and report['restored_pwm']['release_confirmed']
        print(json.dumps(report['restored_pwm']), flush=True)
    except Exception as exc:
        report['restoration_error'] = str(exc)
        print('RESTORATION ERROR: ' + str(exc), flush=True)
    report['finished'] = datetime.datetime.now().isoformat()
    (HERE / 'comparison.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('REPORT: ' + str(HERE / 'comparison.json'), flush=True)

raise SystemExit(0 if report.get('i2c_passed') and report['pwm_restored'] else 1)

