$ErrorActionPreference='Stop'
for($fixGroup=1; $fixGroup -le 6; $fixGroup++) {
    $fixExpression="addpath('output/fixes-2026-10-23'); run_software_group($fixGroup)"
    $fixLog="output/fixes-2026-10-23/matlab-group-$fixGroup.txt"
    $fixProcess=Start-Process -FilePath 'C:/Program Files/MATLAB/R2025b/bin/matlab.exe' -ArgumentList @('-singleCompThread','-batch',('"'+$fixExpression+'"'),'-logfile',('"'+$fixLog+'"')) -WindowStyle Hidden -Wait -PassThru
    Set-Content -LiteralPath "output/fixes-2026-10-23/matlab-group-$fixGroup-exit.txt" -Value $fixProcess.ExitCode
    Get-Content -LiteralPath $fixLog -Tail 5
    if($fixProcess.ExitCode -ne 0){exit $fixProcess.ExitCode}
}
Write-Output 'ALL_SOFTWARE_GROUPS_PASS'
