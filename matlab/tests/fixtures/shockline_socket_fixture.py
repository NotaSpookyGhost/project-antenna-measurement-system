"""One-connection loopback SCPI fixture; never connects to an instrument."""
import socket
import argparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fail-on-trigger', type=int, default=0)
    parser.add_argument('--start-hz', type=float, default=2.39e9)
    parser.add_argument('--stop-hz', type=float, default=2.41e9)
    options = parser.parse_args()
    start, stop, points = options.start_hz, options.stop_hz, 3
    hold = "HOLD"
    triggers = 0
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(120)
        print(f"OFFLINE_FIXTURE_PORT={server.getsockname()[1]}", flush=True)
        connection, _ = server.accept()
        with connection, connection.makefile("rb") as reader:
            for raw in reader:
                command = raw.decode("ascii").strip()
                replies = {
                    "*IDN?": "ANRITSU,MS46122B,OFFLINE_FIXTURE,TEST",
                    ":FORM:DATA?": "ASC",
                    ":SENS1:HOLD:FUNC?": hold,
                    ":SENS1:FREQ:STAR?": str(start),
                    ":SENS1:FREQ:STOP?": str(stop),
                    ":SENS1:SWE:POIN?": str(points),
                    ":SENS1:BAND?": "1000",
                    ":SENS1:CORR:STAT?": "1",
                    ":CALC1:PAR:COUN?": "2",
                    ":CALC1:PAR1:DEF?": "S11",
                    ":CALC1:PAR2:DEF?": "S21",
                }
                if command == ":SENS1:HOLD:FUNC HOLD":
                    hold = "HOLD"
                    continue
                if command == ":TRIG:SING":
                    triggers += 1
                    if triggers == options.fail_on_trigger:
                        break
                    continue
                if command.startswith(":SENS1:FREQ:STAR "):
                    start = float(command.split()[-1])
                    continue
                if command.startswith(":SENS1:FREQ:STOP "):
                    stop = float(command.split()[-1])
                    continue
                if command.startswith(":SENS1:SWE:POIN "):
                    points = int(command.split()[-1])
                    continue
                if command == ":SENS1:FREQ:DATA?":
                    values = [start + (stop-start)*i/(points-1) for i in range(points)]
                    payload = "\n".join(str(f) for f in values).encode()
                elif command in (":CALC1:PAR1:DATA:SDAT?", ":CALC1:PAR2:DATA:SDAT?"):
                    value = "0.5,0.0" if "PAR1" in command else "0.1,0.0"
                    payload = "\n".join([value]*points).encode()
                else:
                    if command not in replies:
                        raise RuntimeError(f"Unexpected command: {command}")
                    connection.sendall((replies[command]+"\n").encode())
                    continue
                length = str(len(payload)).encode()
                response = b"#" + str(len(length)).encode() + length + payload + b"\n"
                for offset in range(0, len(response), 3):
                    connection.sendall(response[offset:offset+3])
    print(f"OFFLINE_FIXTURE_TRIGGERS={triggers}", flush=True)


if __name__ == "__main__":
    main()
