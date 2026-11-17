$ErrorActionPreference='Stop'
$fixHardwareDir='data/validation/acceptance_system_'+[DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss')+'_UTC'
New-Item -ItemType Directory -Path $fixHardwareDir | Out-Null
Set-Content output/retest-6f1fd6d-20261023_162307/hardware-output-dir.txt $fixHardwareDir
$fixExpression="addpath('matlab/tests'); test_acceptance_hardware('COM9','COM6','$fixHardwareDir')"
$fixLog='output/retest-6f1fd6d-20261023_162307/hardware-matlab.txt'
$fixProcess=Start-Process -FilePath 'C:/Program Files/MATLAB/R2025b/bin/matlab.exe' -ArgumentList @('-singleCompThread','-batch',('"'+$fixExpression+'"'),'-logfile',('"'+$fixLog+'"')) -WindowStyle Hidden -Wait -PassThru
Set-Content output/retest-6f1fd6d-20261023_162307/hardware-exit.txt $fixProcess.ExitCode
Get-Content $fixLog -Tail 25
exit $fixProcess.ExitCode

