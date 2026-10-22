# VNA Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Tích hợp VNA S11/S21, SOL và SOLT T/R, Smith, lưu/nạp calibration và quét anten có provenance vào app MATLAB hiện tại.

**Architecture:** Giữ driver FIFO và raw API; scikit-rf giải hiệu chuẩn phía PC. Một VNAController quản lý connection/lease, một VNACalibration dùng chung; workbench dùng Python jobs bất đồng bộ, scan dùng một sweep đồng bộ mỗi góc. Raw và corrected là hai bộ dữ liệu riêng.

**Tech Stack:** MATLAB R2025b classic figure/uicontrol/axes; Python 3.13; pyserial 3.5; scikit-rf 2.1.0; unittest và matlab.unittest. Không yêu cầu RF Toolbox.

**Spec:** [Thiết kế bắt buộc đọc cùng kế hoạch](../specs/2026-10-15-vna-workbench-design.md).

## Global Constraints

- Tasks1–14 đã triển khai và kiểm tra phần mềm; xem [bằng chứng](../../verification/vna-workbench-2026-10-15/verification.md). Checkbox ghi các bước đã thực hiện, checkpoint được giữ trong diff/log, chưa commit/push. A9 phần cứng vẫn NOT_RUN.
- Baseline tham chiếu 7ea2f9e55568c154f2689091c49566858dce3309; đọc HEAD/diff hiện tại, không reset baseline.
- Giữ nanovna_v2.py wire protocol, FIFO ordering/integrity fixes và positioner encoder/hold/zero/travel guards.
- S11/S21 luôn raw. SOL chỉ sửa S11; TR chỉ forward enhanced response, không gọi full two-port.
- Grid thực nguyên Hz dùng floor step; exact profile/grid match; không interpolation/extrapolation.
- 50 kHz..3 GHz, 2..401 points, averages 1..16; scan averages=1.
- Profile schema 1, self-contained JSON tối đa 10 MiB; complex split real/imag; không pickle/eval.
- JSON bỏ derived dB/phase có Inf/NaN; zero complex hợp lệ phải được giữ.
- Một lease VNA; preflight scan trước connect positioner/move; không âm thầm fallback RAW.
- Giữ geometry Metadata.SchemaVersion=2; thêm RFSchemaVersion=1.
- Chỉ chạy mock/fake khi triển khai thông thường. Hardware acceptance là bước riêng có người vận hành.
- Không copy code GPL từ QT/Saver; dùng tài liệu giao thức và scikit-rf BSD-3-Clause.
- RAW phải dùng được nếu thiếu scikit-rf; calibration báo backend unavailable và cách khắc phục.
- Không đổi firmware/cơ khí/framework UI hoặc thêm TDR/de-embedding/full S12/S22.

## Review Focus

1. LOAD/isolated channel bằng zero: JSON round trip giữ zero, không lỗi NaN/Inf serialization — Tasks 1,4,12.
2. Close/đổi mode trong callback khi scan/job chưa kết thúc: không delete controller hoặc mở port thứ hai — Tasks 7,9,11.
3. Profile hash đúng nhưng hệ số bị sửa/engine khác: reject trước activate, giữ profile đang dùng — Task 4.
4. Grid nhìn như giống nhau nhưng khác actual Hz và FIFO đảo thứ tự: pairing đúng, reject mismatch — Tasks 1,5,11.
5. CSV/3D slice lấy nhầm raw khi analysis đã TR: mọi view nhất quán, raw columns vẫn raw — Tasks 11,13.

---

## 0. Cách thực hiện

Thực hiện tuần tự bằng model người dùng chọn. Không tự mở thêm agent/chat hoặc đổi model. Dùng executing-plans và matlab-control. Một task chỉ xong khi test mục tiêu pass và log đã ghi.

| Mốc | Tasks | Kết quả kiểm tra riêng |
|---|---|---|
| M1 | 1–4 | Calibration engine và durable profile offline Python |
| M2 | 5–7 | Bridge jobs và MATLAB calibration/session không GUI |
| M3 | 8–10 | Tab VNA và wizard trong Mock |
| M4 | 11–13 | Scan 2D/3D, persistence và views |
| M5 | 14 | Regression/runbook; software và hardware status riêng |

Chỉ chuyển mốc khi test mốc pass. Nếu cần thay meaning RAW/TR, profile schema, safety hoặc acceptance, báo blocker; không tự giảm yêu cầu. Sai giả định thư viện phải kiểm tra source/docs của bản 2.1.0 và sửa adapter trong phạm vi spec.

### Đọc trước khi sửa

1. AGENTS.md, INSTRUCTIONS_FOR_CODEX.md, CODEX_GUIDE.md.
2. docs/automatic-antenna-measurement-system-master-v4.md.
3. Spec và docs/research-vna-software-options-2026-10-15.md.
4. docs/superpowers/plans/2026-10-15-vna-frequency-grid.md.
5. git status --short, git diff --stat, git log -3 --oneline; giữ thay đổi người khác.

### Commands và bằng chứng

PowerShell tại root repo. $vnaPython là executable đúng environment MATLAB dùng, không phải python ngẫu nhiên trên PATH. Task 2 tạo .venv-vna nếu chưa có; không xóa/recreate env đang có.

~~~powershell
$vnaPython = Join-Path (Get-Location) '.venv-vna/Scripts/python.exe'
& $vnaPython -X utf8 -m unittest discover -s python/tests -p 'test_vna_contracts.py' -v
matlab -batch "addpath('matlab/classes','matlab/app','matlab/tests/fixtures'); set(groot,'DefaultFigureVisible','off'); r=runtests('matlab/tests/TestVNARequest.m'); assertSuccess(r)"
~~~

Ghi command thật, exit code, số pass/fail và giới hạn vào docs/vna-workbench-implementation-log.md. Test dùng tempdir/temporary directory. Không ghi pass khi chưa chạy MATLAB hoặc chỉ syntax-check. Checkpoint cuối task: stage đúng files của task và log, không git add .; commit nếu workflow hiện tại cho phép, không tự push/merge. Nếu chưa được yêu cầu commit, giữ diff và ghi checkpoint.

## 1. Bản đồ file

| File | Trách nhiệm |
|---|---|
| python/vna_contracts.py | request/raw/context validation, wire projection, error codes |
| python/requirements-vna.txt | direct runtime dependencies |
| matlab/classes/vnaPythonBackend.m | pyenv OutOfProcess, lazy imports, không COM |
| python/vna_calibration.py | OnePort/TwoPortOnePath solve/apply, numerical guards |
| python/vna_kit.py | ideal models, characterized Touchstone import |
| python/vna_profile.py | schema/hash/atomic IO/recompute verification |
| python/vna_calibration_api.py | JSON façade cho MATLAB calibration |
| python/vna_jobs.py | một worker, cancellation, terminal retention |
| python/nanovna_bridge.py | giữ API cũ; thêm lock/jobs/zero-reference rejection |
| matlab/classes/VNARequest.m | request/grid/wire encode/decode |
| matlab/classes/VNACalibration.m | draft/profile state và context validity |
| matlab/classes/VNAMockModel.m | deterministic broadband DUT/standard/error model |
| matlab/classes/VNAController.m | shared Calibration, lease, generation, jobs, legacy raw |
| matlab/classes/VNAAnalysis.m | metrics, marker, chọn S21 analysis source |
| matlab/classes/VNAPlotter.m | Smith grid và reusable trace handles |
| matlab/app/VNAWorkbench.m | controls/timer/last/reference measurement |
| matlab/app/VNACalibrationDialog.m | wizard dùng calibration chung |
| matlab/app/AntennaMeasurementApp.m | embed tab, scan policy, mode/close lifecycle |
| matlab/classes/MeasurementOrchestrator.m | preflight/snapshot/atomic point commit |
| matlab/classes/VNADataManager.m | standalone MAT/CSV/metadata/S1P/profile |
| matlab/classes/DataManager.m | append scan RF fields và legacy load |
| python/tests/vna_fixtures.py | independent synthetic truth/errors, không serial |
| matlab/tests/fixtures/ScriptedVNAController.m | fake jobs/errors/counters subclass |
| matlab/tests/fixtures/TrackingVNAPositioner.m | connect/move counters, reuse mock interfaces |
| matlab/tests/run_vna_software_tests.m | explicit software-only allowlist |

Không tạo generic plugin/event bus/database; không dồn engine/profile vào App. Test files cụ thể nằm trong từng task.

## 2. API giữa các task

Dict/struct dùng đúng schema spec; không đổi tên field ở bên nhận.

### Python core và JSON

~~~text
vna_contracts:
  VNAError(code: str, message: str)
  validate_request(request: dict) -> dict
  actual_grid(request: dict) -> list[int]
  validate_raw(raw: dict) -> dict
  validate_context(context: dict) -> dict
vna_calibration:
  build_engine(draft: dict) -> skrf.Calibration
  coefficients_to_wire(engine) -> dict
  apply_engine(engine, raw: dict, algorithm: str) -> dict
vna_kit:
  ideal_kit(frequency_hz: list[int]) -> dict
  load_kit(paths: dict, frequency_hz: list[int], algorithm: str, name: str) -> dict
vna_profile:
  create_profile(draft: dict) -> dict
  validate_profile(profile: dict) -> dict
  save_profile(path: str, profile: dict) -> None
  load_profile(path: str) -> dict
vna_calibration_api:
  backend_info_json() -> str
  kit_json(paths_json: str, frequency_json: str, algorithm: str, name: str) -> str
  solve_json(draft_json: str) -> str
  apply_json(profile_json: str, raw_json: str) -> str
  save_json(path: str, profile_json: str) -> str
  load_json(path: str) -> str
~~~

build_engine solve nhưng không tạo UUID/time hoặc I/O. create_profile sinh UUID/time và seal sau solve. validate_profile rebuild không đổi identity. Không circular import: contracts ← kit/calibration ← profile ← API.

Mọi *_json trả status/payload hoặc status/code/message. Apply payload: corrected_s11={real,imag}, corrected_s21={real,imag} hoặc null cho SOL, channel_state={s11,s21}. Backend info trả engine/adapter version, không initialize instrument. Cache tối đa một validated engine theo content hash sau validation đầy đủ; lần đầu không tin hash input. Load disk luôn validate/rebuild, không bypass bằng cache.

Draft schema: name, algorithm, frequency_hz, z0_ohm, context, kit, standards; chưa có profile_id/created_at_utc/coefficients/hash. Validation mặc định NOT_CHECKED. Standard order trong adapter short,open,load[,thru], không phụ thuộc thứ tự key JSON.

### Python jobs

~~~text
vna_jobs.JobManager(acquire_once, configure, io_lock):
  start(request: dict, generation: int) -> dict
  poll(job_id: str) -> dict
  cancel(job_id: str) -> dict
nanovna_bridge:
  start_sweep_json(request_json: str, generation: int) -> str
  poll_sweep_json(job_id: str) -> str
  cancel_sweep_json(job_id: str) -> str
~~~

States RUNNING|SUCCEEDED|FAILED|CANCELLED. Payload luôn job_id/generation/state; SUCCEEDED có raw, FAILED có error={code,message}, CANCELLED không có raw. Giữ terminal result đến job tiếp theo; poll lặp không mất dữ liệu. Poll/cancel không lấy I/O lock.

Callbacks JobManager: configure(request:dict)->None và acquire_once()->raw dict. Bridge adapters gọi API đồng bộ hiện tại với worker identity hợp lệ; worker giữ I/O lock cho cả nhóm averages. Mỗi raw sweep có metadata trước validation; averaged result nhận AcquisitionId mới, Averages thực tế và timestamp sau sweep cuối.

Trước khi start trả thành công, register active job dưới state mutex; mọi legacy hardware call kiểm tra active job và I/O lock. Worker token/thread identity là đường duy nhất vượt active-job guard. Không có khe race trước worker acquire lock; không giữ state mutex khi chờ I/O. Cancel check trước configure, trước/sau từng sweep và trước publish.

### MATLAB

~~~text
VNARequest.normalize(request) -> request
VNARequest.actualGrid(request) -> row double Hz
VNARequest.toWire(rawSweep) -> scalar struct
VNARequest.fromWire(wireRaw) -> legacy-compatible rawSweep
vnaPythonBackend(requireCalibration logical) -> struct(Bridge,CalibrationApi,Version)

VNACalibration(ownerGetter function_handle):
  beginCollection(algorithm,kit,context,request)
  recordStandard(name,rawSweep)
  solve() -> profile
  activate(request,context,confirmed logical)
  disable(); invalidate(reason); save(path); load(path)
  validateFor(policy,request,context) -> profileSnapshot
  apply(rawSweep,profileSnapshot) -> measurement
  getProfile() -> profile value copy
  State, StatusReason (read only)

VNAController additions:
  Calibration VNACalibration (read only), MockRFErrors logical=false
  claim(owner char) -> lease struct(Owner,Id)
  release(lease); assertLease(lease)
  getContext() -> context struct
  setRFContext(instrumentLabel,rfPathId,referencePlane)
  beginSweep(request,lease) -> jobId char
  pollSweep(jobId,lease) -> MATLAB job struct
  cancelSweep(jobId,lease)
  isBusy() -> logical
  Owner, Generation (read only)
~~~

Lease ID là UUID, owner workbench|calibration|scan. Claim occupied luôn BUSY kể cả cùng owner. App truyền lease vào orchestrator, không claim lại; release ID sai không thay owner. Legacy connect(port,lease), disconnect(lease), identify(lease), configureSweep(start,stop,points,lease), acquireSweep(...,lease), acquireSingle(lease) thêm optional cuối; omit chỉ hợp lệ khi owner empty. Giữ calls cũ không argument/ba argument của acquireSweep bằng parser rõ ràng. Không đổi constructor defaults.

acquireAtFrequency(freqHz,lease) cũng chuyển lease xuống configure/acquire; không có đường public hardware nào vượt guard. setMockAngle/setMockOrientation giữ API hiện tại cho scan, nhưng job phải chụp góc ngay lúc beginSweep, không đọc góc mutable trong lúc worker chạy.

getContext dùng cached identity sau connect, không mở COM trong poll. Register không hỗ trợ là null, không giả số0. Compare mode/instrument_label/device_variant/protocol/hardware/firmware/path/plane/mock_model; COM chỉ provenance. setRFContext và thay MockRFErrors chỉ idle và invalidate calibration.

VNACalibration giữ canonical profile JSON string private từ Python; không decode→jsonencode toàn profile rồi dùng lại hash ở MATLAB. Snapshot là value struct có Profile (decoded) và CanonicalJSON (original); RAW snapshot empty. Measurement.CalibrationProfile là decoded profile, thêm CalibrationProfileJSON cho persistence; đây không phải field trong .vnacal.json. Save/apply dùng original JSON.

ownerGetter chặn mutating operations khi owner workbench/scan; wizard owner calibration được phép. apply/validateFor read-only. RAW measurement dùng cùng schema với correction/profile empty. Job MATLAB giữ cùng state và Raw/error fields sau decode; names JobId,Generation,State,Raw,Error, Error.Code/Message. Job terminal error map thành VNA:<code> tại caller, không throw mất terminal state.

## Task 1 — Request/raw contracts và tính toàn vẹn

**Files:** tạo python/vna_contracts.py, python/tests/test_vna_contracts.py, matlab/classes/VNARequest.m, matlab/tests/TestVNARequest.m; sửa python/nanovna_bridge.py:_result_to_dict và python/tests/test_sweep_integrity.py.

**Interfaces:** consume driver SweepResult; produce contracts/VNARequest §2. Chưa dùng skrf.

- [x] Viết tests fractional/NaN/range, actual grid, inverted FIFO, duplicate/missing index, FWD=0 và zero response với nonzero FWD:
  ~~~python
  self.assertEqual(actual_grid(dict(start_hz=100000,stop_hz=100010,points=4,averages=1)), [100000,100003,100006,100009])
  self.assertNotIn("s11_db", validate_raw(zero_response_wire))
  self.assertEqual(validate_raw(zero_response_wire)["s11_real"], [0.0]*4)
  ~~~
  MATLAB assert actualGrid equals [100000 100003 100006 100009]; roundtrip vectors thành row, complex zero giữ nguyên, derived zero phase NaN.
- [x] Chạy Python test mới bằng Python hiện có trước Task 2, MATLAB TestVNARequest; expected FAIL thiếu module/class. Existing integrity tests phải pass trước sửa.
- [x] Implement signatures §2; finite Re/Im, increasing grid, length N, complete; reject Python bool thay integer; ZERO_REFERENCE trước ratio conversion. S11 magnitude>1 không tự thành invalid. Giữ pairing sorted index hiện tại. Bridge raw result append captured_at_utc, averages=1, mode=Real, acquisition_id; preserve existing keys. Mock fromWire dùng metadata do mock generator cung cấp, không gắn nhầm Real.
- [x] Chạy test_vna_contracts.py, test_sweep_integrity.py bằng unittest discover pattern từng file và MATLAB TestVNARequest theo command mẫu; expected PASS, không COM.
- [x] Checkpoint “feat(vna): validate requests and preserve raw sweep integrity”; files đúng danh sách task.

## Task 2 — SOL engine và environment MATLAB

**Files:** tạo python/requirements-vna.txt, python/vna_calibration.py, python/vna_kit.py (ideal only), python/tests/vna_fixtures.py, python/tests/test_calibration_engine.py, matlab/classes/vnaPythonBackend.m, matlab/tests/TestVNABackend.m; sửa .gitignore thêm .venv-vna/.

**Interfaces:** consume Task 1; produce build_engine, coefficients_to_wire, apply_engine cho SOL_1PORT, ideal_kit và backend helper. CalibrationApi tạm empty đến Task 4.

- [x] Viết synthetic test independent theo spec §6, 11 frequencies, DUT gamma khác các chuẩn. Assert max(abs(corrected-truth))<=1e-10, corrected_s21 null, raw unchanged. Test identical standards, wrong grid, nonfinite và cond>1e12 reject đúng code.
- [x] Chạy test_calibration_engine.py, expected FAIL thiếu SOL implementation. Phân biệt dependency missing với assertion failure.
- [x] Tạo env nếu chưa có bằng base Python đã xác minh; inspect env cũ trước, không recreate:
  ~~~powershell
  & 'C:/Users/Spooky Laptop/AppData/Local/Programs/Python/Python313/python.exe' -m venv .venv-vna
  & ./.venv-vna/Scripts/python.exe -m pip install -r python/requirements-vna.txt
  ~~~
  requirements: scikit-rf==2.1.0, pyserial==3.5. Pip resolve NumPy/SciPy tương thích; ghi actual versions vào log, không thay global packages.
- [x] Implement SOL/ideal kit theo spec. Backend helper khi Python chưa Loaded ưu tiên env repo/OutOfProcess; đã Loaded thì kiểm tra đúng env đó. Không tự terminate session khác; thiếu dependency báo BACKEND_UNAVAILABLE kèm executable/restart guidance. requireCalibration=false không import skrf; imports theo python.*.
- [x] Chạy test_calibration_engine.py; MATLAB TestVNABackend kiểm tra đúng version2.1.0 và một SOL solve offline qua pyenv thực (direct module đến Task 4). Expected PASS. MATLAB không khả dụng thì ghi BLOCKED, không đánh dấu gate pass.
- [x] Checkpoint “feat(vna): add offline SOL calibration engine”.

## Task 3 — TR adapter và characterized kit

**Files:** sửa python/vna_calibration.py, python/vna_kit.py, python/tests/vna_fixtures.py; tạo python/tests/test_calibration_tr.py, python/tests/test_vna_kit.py.

**Interfaces:** extend Task 2 cho TR_ENHANCED_RESPONSE và load_kit; paths keys open/short/load/thru; SOL không cần thru.

- [x] Viết test independent error formula với DUT gamma khác0 và complex S21; assert cả hai max complex error<=1e-10. Missing/zero thru và degenerate OSL reject. Ideal OSL internal S22=gamma; measured placeholders không xuất thành reverse measurement.
- [x] Chạy hai test files; expected FAIL chưa có TR/import.
- [x] Implement TwoPortOnePath(source_port=1,n_thrus=1), OSL ideal mirrored diagonal, apply single network. **Chạy thật fixture trên engine2.1.0**; đọc source không thay test. Không dùng tuple forward/reverse giả để đạt assertion.
- [x] Implement Touchstone parse bằng skrf.Network, đúng ports/exactgrid/z0=50 real/finite; embed models và basename/SHA256. Test Unicode path và xóa nguồn kit sau embed vẫn solve; reject interpolation/renormalization ngầm.
- [x] Chạy test_calibration_tr.py, test_vna_kit.py, test_calibration_engine.py; expected PASS.
- [x] Checkpoint “feat(vna): add forward TR calibration and characterized kits”.

## Task 4 — Durable profile và JSON API

**Files:** tạo python/vna_profile.py, python/vna_calibration_api.py, python/tests/test_calibration_profile.py, python/tests/test_calibration_api.py; cập nhật backend helper import CalibrationApi.

**Interfaces:** consume Tasks 1–3; produce profile/JSON functions §2, canonical bytes/hash spec §4.3.

- [x] Test solve→save→process exit→load→apply qua subprocess mới, tránh cache che lỗi. Assert raw/models preserved và max correction delta<=1e-12.
- [x] Test JSON lỗi, >10MiB, schema sai/engine, complete sai, altered coefficients với hash đã tính lại, Unicode, failed os.replace, zero transmission. Schema1 reject unknown top-level fields, không silently drop. Failed load không thay active in-memory profile.
- [x] Chạy test_calibration_profile.py, test_calibration_api.py; expected FAIL thiếu API/module.
- [x] Implement strict parse_constant reject NaN/Infinity, hash exclude only content_sha256, rebuild coefficients compare rtol1e-10/atol1e-12. Never mutate input. Atomic temp sibling/os.replace; failed save giữ old bytes và cleanup temp.
- [x] Implement envelopes và one-entry validated engine cache. Missing dependency BACKEND_UNAVAILABLE; profile/raw failures INVALID_PROFILE/INVALID_SWEEP hoặc specific code. Unexpected exception không trả OK; giữ traceback ở developer log.
- [x] Chạy profile/API/all engine tests, expected PASS/no COM. Kiểm tra output JSON bằng parser chuẩn độc lập.
- [x] Checkpoint “feat(vna): persist and validate calibration profiles”.

## Task 5 — Bridge worker, averages và cancellation

**Files:** tạo python/vna_jobs.py, python/tests/test_vna_jobs.py; sửa python/nanovna_bridge.py.

**Interfaces:** consume Task 1; produce JobManager/bridge jobs §2; giữ legacy API.

- [x] Viết Event-controlled fake tests, không sleep dài: +1 và -1 average complex→0; grid đổi giữa averages fails; second start BUSY; legacy disconnect/configure BUSY; cancel trước configure/during read/trước publish; repeat poll terminal; worker exception releases lock.
  ~~~python
  self.assertAlmostEqual(result["raw"]["s11_real"][0], 0.0)
  self.assertEqual(cancelled["state"], "CANCELLED")
  self.assertNotIn("raw", cancelled)
  ~~~
- [x] Chạy test_vna_jobs.py; expected FAIL thiếu jobs.
- [x] Implement one daemon worker/state mutex/shared nonblocking RLock; reserve slot trước launch. Guard mọi public hardware call, kể cả auto-detect có mở device. Poll/cancel không I/O. Configure một lần/job, mỗi sweep đủ điểm; averaged result có timestamp/id; values_per_freq=1.
- [x] Cancellation cooperative; không kill thread/close serial concurrent/publish partial average. Unknown job INVALID_REQUEST. Publish chỉ khi cancel flag chưa set dưới mutex.
- [x] Chạy test_vna_jobs.py và existing Python suite, expected PASS. Fake transport có bounded read kiểm tra terminal cleanup/STOP latency; ghi latency đo được, không suy ra hardware latency.
- [x] Checkpoint “feat(vna): add cancellable sweep jobs and complex averaging”.

## Task 6 — MATLAB calibration state và profile façade

**Files:** tạo matlab/classes/VNACalibration.m, matlab/tests/TestVNACalibration.m; cập nhật matlab/tests/TestVNABackend.m.

**Interfaces:** consume JSON API/VNARequest; produce VNACalibration §2. Canonical JSON private, snapshots value copies.

- [x] Test NONE→COLLECTING→READY→ACTIVE→DISABLED/STALE, load→READY. Changed band/path/mode/firmware/reconnect không autoactive; explicit confirmed Apply sau load/reconnect. Owner scan/workbench blocks load/solve/disable, read-only apply permitted.
- [x] Test MATLAB↔Python save/load delta<=1e-12, Unicode, zero serialization, failedload retains prior profile, SOL S21 RAW.
- [x] Chạy TestVNACalibration theo MATLAB command mẫu; expected FAIL thiếu class/method.
- [x] Implement stable VNA:<code>, private draft/JSON, transactional load/solve. Recapture invalidates active correction; giữ prior saved profile, không tự apply lại. validateFor(RAW) trả empty snapshot; SOL/TR require ACTIVE và matching algorithm/context/grid. Averages khác không stale.
- [x] Chạy TestVNACalibration/TestVNABackend, expected PASS không COM. Numerical integration dùng Python thật; không stub rồi tuyên bố solver pass.
- [x] Checkpoint “feat(vna): manage calibration state and profile reuse in MATLAB”.

## Task 7 — Controller lease, async façade và bounded mock

**Files:** sửa matlab/classes/VNAController.m; tạo matlab/classes/VNAMockModel.m, matlab/tests/TestVNAControllerSession.m, matlab/tests/fixtures/ScriptedVNAController.m.

**Interfaces:** consume Tasks 1/5/6; produce additions §2. Mock jobs không cần Python trừ khi solvecal.

- [x] Test wrong/missing lease rejects trước hardware call; occupied claim BUSY; wrong-ID release giữ owner; generation đổi rejects kết quả cũ; unowned legacy calls vẫn chạy.
- [x] Test MockRFErrors=false giữ legacy pattern; true toàn dải 50 kHz..3GHz finite, standards/DUT đúng spec formula, context model tag khớp. Thu chuẩn không đổi DUT tiếp theo; request snapshot không thay đổi.
- [x] Chạy TestVNAControllerSession; expected FAIL thiếu interface.
- [x] Implement shared Calibration/lazy backend, cached identity, generation increment connect/disconnect/replacement, context setters. Jobs map envelopes/raw metadata; synchronous error-enabled mock dùng cùng helper. VNAMockModel.generate(request,phi,theta,is3D) trả raw theo spec, no noise; legacy branch không thay số học ngoài grid fix.
- [x] ScriptedVNAController subclass Mock-only overrides jobs/acquisition, queues terminal/errors/counters. Test busy mutation/disconnect/legacy/new methods, expected PASS. Đây là fixture, không production backend thứ hai.
- [x] Checkpoint “feat(vna): coordinate controller sessions and calibrated mock data”.

## Task 8 — RF metrics và reusable Smith plots

**Files:** tạo matlab/classes/VNAAnalysis.m, matlab/classes/VNAPlotter.m, matlab/tests/TestVNAAnalysis.m, matlab/tests/TestVNAPlotter.m.

**Interfaces:** VNAAnalysis.metrics(fHz,s11,s21,z0) trả row fields S11_dB,ReturnLoss_dB,VSWR,ZOhm,S11_PhaseDeg,S21_dB,S21_PhaseDeg; nearestIndex(fHz,targetHz) trả index; selectScanS21(scanData) trả complex matrix. VNAPlotter(parent), render(measurement,reference,markerIndex,secondaryMode), delete().

- [x] Test gamma 0,+1,-1,+j,1.1: matched Z50/RLInf/VSWR1; short Z0; +j Z50j; >1 VSWRNaN; zero phaseNaN. Marker tie tần số thấp hơn; không mutate raw. Source selector legacy/RAW/SOL→S21; TR→CorrectedS21, thiếu corrected TR throws.
- [x] Test invisible Smith axes XData/YData=real/imag; equal aspect; >1 point visible bằng giới hạn trục mở rộng; render lặp lại không tăng số line handles; reference khác grid dùng XData riêng.
- [x] Chạy TestVNAAnalysis/TestVNAPlotter theo mẫu MATLAB; expected FAIL thiếu classes.
- [x] Implement formulas spec §7. Smith grid từ constant resistance/reactance mapping gamma=(z-1)/(z+1), handles tái sử dụng; display floor-120 only. Secondary Phase/VSWR toggle; labels theo channel. Không RF Toolbox hoặc đọc instrument/profile từ plotter.
- [x] Chạy tests expected PASS; lưu một screenshot Mock ở temporary report để xem labels/marker/layout. Screenshot không thay math test.
- [x] Checkpoint “feat(vna): add RF metrics and Smith visualization”.

## Task 9 — Workbench và app lifetime

**Files:** tạo matlab/app/VNAWorkbench.m, matlab/tests/TestVNAWorkbench.m; sửa matlab/app/AntennaMeasurementApp.m:createUI/handleVNAModeChange/toggleVNAConnect/delete.

**Interfaces:** VNAWorkbench(parentTabGroup,vna,onStatus); startSingle(request), startContinuous(request), stop(), poll(), setController(vna), requestClose()→ready logical, keepReference(), loadReference(path); read-only LastMeasurement,State,IsBusy. App thêm requestClose(), finalizeCloseIfReady().

- [x] Test scripted RUNNING→SUCCEEDED single; continuous chờ terminal; STOP discards late result; failure preserves LastMeasurement; sai job/generation ignored; tick không acquire/configure serial.
- [x] Test close pending giữ controller/figure đến terminal; busy mode/connect rejects; idle close không timer còn sót; replacement cập nhật cả workbench/orchestrator references.
- [x] Chạy TestVNAWorkbench; expected FAIL thiếu tab/class.
- [x] Embed classic UI spec §7, validate trước claim, offline hiển thị yêu cầu kết nối. Mock demo bật MockRFErrors chỉ idle, nhãn MÔ PHỎNG; connection ở app, không controller thứ hai. Timer0.1s fixedSpacing/BusyMode drop, render<=5Hz và flush kết quả cuối.
- [x] Lease kéo dài toàn Continuous; generation/request snapshot; build uniform measurement raw hoặc Calibration.apply khi ACTIVE. Raw/Corrected chỉ thay view. Reference là copy; loadReference implementation nối ở Task 12, giai đoạn này keepReference hoạt động.
- [x] Wire close request/finalizer, không busy-wait callback; controller delete chỉ sau drain. Guard isvalid/cleanup timer; handle mode switch chỉ idle. Task 11 bổ sung test close từ active synchronous scan, không tuyên bố đã kiểm chứng case đó tại task này.
- [x] Chạy TestVNAWorkbench + TestScan3DGUI/TestScanStopGUI; expected PASS. Xem tab Mock ở 1200×780 và resize; tests không bắt buộc modal dialogs.
- [x] Checkpoint “feat(vna): embed live VNA workbench with safe lifecycle”.

## Task 10 — Calibration wizard và profile controls

**Files:** tạo matlab/app/VNACalibrationDialog.m, matlab/tests/TestVNACalibrationDialog.m; sửa matlab/app/VNAWorkbench.m.

**Interfaces:** VNACalibrationDialog(parent,vna,onChanged); begin(algorithm,kit,context,request), capture(name), poll(), solve(), apply(confirmed), requestClose()→ready. Workbench thêm openCalibration(), loadProfile(path), saveProfile(path), setCorrectionEnabled(enabled,confirmed).

- [x] Test wizard giữ lease giữa OPEN/SHORT/LOAD, scan claim BUSY, recapture invalidates, thiếu THRU chặn TR. Cancel/error/close chỉ release sau terminal. Controls theo state; profile đã nạp không autoactive.
- [x] Test import kit characterized, grid sai reject/no fallback sang ideal; thiếu backend có thông báo khắc phục, raw vẫn chạy.
- [x] Chạy TestVNACalibrationDialog; expected FAIL thiếu wizard.
- [x] Implement shared controller/cal/jobs, averages mặc định4, lưới thực preview. Hướng dẫn O/S/L và gắn tải 50 ohm vào Port 2 trong TR; timestamp/checkmark từng chuẩn, NOT_CHECKED label, identity/path/plane inputs. UI filepicker chỉ boundary, tests dùng đường dẫn truyền rõ ràng.
- [x] Lease vẫn giữ khi người dùng thay chuẩn. Wizard poll timer chỉ poll job riêng; không để timer của workbench poll cùng capture. Apply thành công close/release; yêu cầu tháo chuẩn và nối DUT trước phép đo mới. Đổi cáp làm STALE, load/reconnect cần Apply có xác nhận.
- [x] Chạy TestVNACalibrationDialog/TestVNACalibration/TestVNAWorkbench; expected PASS.
- [x] Checkpoint “feat(vna): add SOL and TR calibration workflow”.

## Task 11 — Calibrated scans, preflight và partial rows

**Files:** sửa matlab/classes/MeasurementOrchestrator.m:startScan/startScan3D, matlab/app/AntennaMeasurementApp.m:startScan/requestClose; tạo matlab/tests/TestScanVNACalibration.m, matlab/tests/fixtures/TrackingVNAPositioner.m; mở rộng ScriptedVNAController.

**Interfaces:** Orchestrator CalibrationPolicy='RAW', startScan(lease=[])→scanData; nhánh 3D private nhận cùng lease/snapshot. Consume Calibration.validateFor/apply và VNAAnalysis.selectScanS21; giữ old public calls.

- [x] Test busy/missing/profile stale trước kết nối positioner/move: verifyEqual(positioner.ConnectCount,0), verifyEqual(positioner.MoveCount,0). Entry point trực tiếp của orchestrator entry cũng có gate.
- [x] Test RAW regression, SOL chỉ corrected S11, TR SelectedS21 lấy corrected S21, snapshot ID không đổi; lưới thực [100000 100003 100006 100009]. Failing third raw/correction/grid giữ đúng 2 rows nhất quán. Một row đã commit vẫn lưu, metrics không đủ dữ liệu NaN.
- [x] Test close trong scan callback: abort requested; controller còn valid đến unwind, release đúng một lần, finalizer sau đó. Lỗi initialization releases lease tự claim.
- [x] Chạy TestScanVNACalibration; expected FAIL thiếu policy/partial/preflight.
- [x] Claim VNA và preflight trước khi app tự kết nối positioner hoặc orchestrator initialize thiết bị. Lease mượn từ caller không được callee release; mỗi owner có onCleanup. Thứ tự: kết nối VNA → kiểm tra calibration → các positioner gates hiện có. Chụp canonical JSON một lần; policy/cal mutation giữa scan bị chặn.
- [x] 2D dùng lưới thực từ sweep thay linspace. Raw+corrected commit sau validation; không ghi halfrow. Source selector dùng cho SelectedS21/phase/normalized/Analysis/callback; geometry schema 2 giữ nguyên, append RF metadata trong spec. Lỗi RF giữ partial/status/nguyên nhân lỗi; zero rows không thay prior dataset của app.
- [x] Chạy TestScanVNACalibration + TestScan3D/TestScanStopGUI/TestManualHoming/TestPositionerLimits/TestMoveTimeout/TestPatternPartialPlot; expected PASS. Không giảm motion guard thresholds.
- [x] Checkpoint “feat(scan): apply VNA profiles with atomic raw and corrected records”.

## Task 12 — Standalone persistence/export và reference load

**Files:** tạo matlab/classes/VNADataManager.m, matlab/tests/TestVNADataManager.m; sửa matlab/app/VNAWorkbench.m.

**Interfaces:** static saveMeasurement(baseDir,measurement)→files struct, loadMeasurement(path)→measurement, writeS1P(path,fHz,s11,comments). Files keys Directory,Mat,Csv,Metadata,RawS1P,CorrectedS1P,Profile; unavailable emptychar.

- [x] Test raw/cal roundtrip<=1e-12, Unicode, collision directory riêng, zero preserved; CSV/MAT đủ toàn bộ grid/raw/corrected ReIm; metadata JSON hữu hạn. Parse S1P bằng skrf integration test xác nhận frequency/complex/z0.
- [x] SOL có corrected S11 export nhưng không fabricated corrected S21; không DUT.s2p. Broken .mat shape/schema reject, giữ prior active/reference.
- [x] Chạy TestVNADataManager; expected FAIL thiếu class.
- [x] Implement bundle theo spec: UTC+UUID folder, folder tạm rồi finalize thành công; không overwrite. MAT chứa measurement và original CalibrationProfileJSON; profile save qua Python API dùng JSON gốc, không rehash struct MATLAB.
- [x] Wire save/reference. Load validates measurement schema/arrays, không autoactivate/calibrate lại; reference copy dùng own grid. CSV derived nonfinite rõ Inf/-Inf/NaN, metadataJSON chỉ finite metadata, arrayscomplex finite.
- [x] Chạy TestVNADataManager/TestVNAWorkbench reference case; expected PASS.
- [x] Checkpoint “feat(vna): export reproducible standalone measurements”.

## Task 13 — Scan export, legacy load và 3D views

**Files:** sửa matlab/classes/DataManager.m, matlab/app/AntennaMeasurementApp.m:updateFinalResults/recordLive3D/plotMeasured3D/select3DSlice; tạo matlab/tests/TestScanVNAData.m; mở rộng matlab/tests/TestScan3DGUI.m.

**Interfaces:** existing DataManager signatures giữ nguyên; consume RF fields/source selector Task 11. Append CSV fields, không đổi nghĩa raw columns.

- [x] Test raw S21=-20dB, corrected S21=-17dB: CSV old s21_db=-20; corrected mới/analysis=-17. slice TR/peak/RF monitor trực tiếp đều-17; SOL dùng raw S21. MAT toàn bộ complex arrays, metadata profile ID/channel state/source.
- [x] Test legacy 2D/3D thiếu fields mới load không reprocess bằng profile đang active; UNKNOWN_RAW_LEGACY provenance, raw không đổi, geometry schema 2 unchanged.
- [x] Chạy TestScanVNAData/TestScan3DGUI case mới; expected FAIL sai source/export.
- [x] Extend saveScanDataset/saveScan3DDataset/metadata: append corrected_s11_re, corrected_s11_im, corrected_s21_re, corrected_s21_im, corrected_s21_db, analysis_s21_db, calibration_profile_id, s11_channel_state, s21_channel_state. Lưu full profile cùng scan bằng JSON gốc như Task 12. Khi không có correction, numerical CSV fields để trống và channel state RAW; không copy raw sang corrected.
- [x] 3D/slice dùng VNAAnalysis.selectScanS21; không raw trực tiếp recompute cho TR. RFmonitor labels provenance. Load chỉview, không recorrect.
- [x] Chạy TestScanVNAData/TestScan3DData/TestScan3DGUI và DataManager tests hiện có nếu có; expected PASS.
- [x] Checkpoint “feat(scan): preserve calibration provenance in exports and views”.

## Task 14 — Regression allowlist và bàn giao

**Files:** tạo matlab/tests/run_vna_software_tests.m, docs/vna-workbench-user-guide.md, docs/vna-workbench-hardware-qualification.md; sửa CODEX_GUIDE.md, INSTRUCTIONS_FOR_CODEX.md, implementation log.

**Interfaces:** không product API mới; A1–A8 software, A9 physical riêng.

- [x] Tạo allowlist rõ ràng toàn bộ TestVNA*/TestScanVNA* mới và tests đã chọn bên dưới. Inspect mỗi path trước chạy; không master runner/test_saa2n/test_python_bridge/real ESP32.
- [x] Chạy final:
  ~~~powershell
  & ./.venv-vna/Scripts/python.exe -X utf8 -m unittest discover -s python/tests -p 'test_*.py' -v
  matlab -batch "addpath('matlab/classes','matlab/app','matlab/tests','matlab/tests/fixtures'); set(groot,'DefaultFigureVisible','off'); run_vna_software_tests"
  git diff --check
  git status --short
  ~~~
  MATLAB allowlist cũ: TestScanGeometry, TestPositionerLimits, TestScan3D, TestScan3DData, TestScan3DGUI, TestPositionerResponse, TestManualHoming, TestScanStopGUI, TestMoveTimeout, TestPatternPartialPlot. Thêm scripts test_pattern_analyzer, test_orchestrator_mock, test_scan_direction_and_abort sau inspect phiên bản hiện tại. assertSuccess tất cả; không swallow assertion lỗi.
- [x] Ghi versions/test counts/exit codes/elapsed và điều kiện chưa giải quyết. Sau fix chỉ rerun tests bị ảnh hưởng và gate cần thiết. Inspect data/; chỉ cleanup artifacts chính test tạo, giữ raw của người dùng.
- [x] User guide: setup env, live controls, lưới thực, SOLvsTR, ideal/characterized, capture sequence, save/load/contextconfirm, đổi cáp/stale, RAWvsCorrected, scan policy, exports và backend errors.
- [x] Hardware runbook: VNA đứng yên trước, không motor; identity/firmware/kit/cable/referenceplane, raw standards/DUT/QT reference, independent validation, spec§9thresholds, STOP latency/repeatability. A9 NOT_RUN/NOT_QUALIFIED đến khi có bằng chứng thực tế và criteria được người phụ trách chấp nhận. Kế hoạch phần mềm không cấp quyền motor motion.
- [x] Diff cuối review: thay đổi raw, reverse giả, guards bị hạ, leaks, nhãn sai. Link screenshots/tests; SOFTWARE_VERIFIED chỉ khi A1–A8 pass thực tế, A9 báo riêng.
- [x] Checkpoint “docs(vna): document verified workflow and hardware qualification gates”; không tựpush/deploy.

## Coverage và tự rà soát

| Requirement | Tasks / evidence |
|---|---|
| A1 jobs/live/STOP/ownership | 5,7,9,11 |
| A2 independent SOL/TR numerical | 2,3,7 |
| A3 durable cross-session profile | 4,6,12 |
| A4 invalid inputs/context/profile, state preservation | 1,3,4,6,7,10,11 |
| A5 math/Smith/marker/reference | 8,9,12 |
| A6 raw/SOL/TR scan, lưới thực, partial/snapshot | 11,13 |
| A7 nohardware mock/legacy regressions | mọi task và 14 |
| A8 precision/Unicode/export/legacy | 4,12,13 |
| A9 real qualification | Task 14 runbook, không mock completion |
| Review Focus 1–5 | 1/4/12;7/9/11;4;1/5/11;11/13 |

API fragments là contracts, không phải implementation đã có. Mọi test file mới phải được viết và chạy. Timeline theo gate; tài liệu không chứng minh độ chính xác RF hoặc sweep rate thực.



