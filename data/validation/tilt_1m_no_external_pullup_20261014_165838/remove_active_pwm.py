"""Remove the retired optional transport; preserve all I2C/hold/motion code."""
from pathlib import Path

root=Path(__file__).resolve().parents[3]
main=root/'firmware/positioner_v3_hold/src/main.cpp'


def without_pwm(lines):
    result=[]
    i=0
    while i<len(lines):
        directive=lines[i].strip()
        if directive not in ('#ifdef TILT_PWM_ENABLED','#ifndef TILT_PWM_ENABLED'):
            result.append(lines[i]); i+=1; continue
        start=i+1; depth=1; middle=None; end=start
        while depth:
            token=lines[end].strip()
            if token.startswith(('#if ','#ifdef ','#ifndef ')): depth+=1
            elif token=='#endif': depth-=1
            elif token=='#else' and depth==1: middle=end
            if depth: end+=1
        if directive.startswith('#ifndef'):
            chosen=lines[start:middle if middle is not None else end]
        else:
            chosen=lines[middle+1:end] if middle is not None else []
        result.extend(without_pwm(chosen)); i=end+1
    return result


text=''.join(without_pwm(main.read_text(encoding='utf-8').splitlines(keepends=True)))
anchor='  else if (cmd == "ZERO" || cmd == "0") {'
assert text.count(anchor)==1
text=text.replace(anchor,
    '  // Retired commands must not fall through to TILT <angle> parsing.\n'
    '  else if (cmd.startsWith("TILT PWM")) {\n'
    '    Serial.println("ERR: UNSUPPORTED_COMMAND; TILT USES I2C");\n'
    '  }\n'+anchor)
assert 'TILT_PWM_ENABLED' not in text and 'as5600_pwm.h' not in text
main.write_text(text,encoding='utf-8')

bus=root/'firmware/positioner_v3_hold/src/as5600_bus.h'
text=bus.read_text(encoding='utf-8')
start=text.index('  // Only volatile full-turn/CONF setup writes')
end=text.index('  bool readRegisters',start)
bus.write_text(text[:start]+text[end:],encoding='utf-8')

ini=root/'firmware/positioner_v3_hold/platformio.ini'
text=ini.read_text(encoding='utf-8')
assert text.count('[env:tilt-pwm]')==1
ini.write_text(text.split('[env:tilt-pwm]')[0].rstrip()+'\n',encoding='utf-8')
print('Removed active PWM branches/environment/configuration writes; I2C retained.')
