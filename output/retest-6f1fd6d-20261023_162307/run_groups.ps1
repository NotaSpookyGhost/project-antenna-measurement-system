$ErrorActionPreference='Stop'
for($fixGroup=1; $fixGroup -le 6; $fixGroup++) {
    $fixExpression="addpath('output/retest-6f1fd6d-20261023_162307'); run_software_group($fixGroup)"
    $fixLog="output/retest-6f1fd6d-20261023_162307/matlab-group-$fixGroup.txt"
    $fixProcess=Start-Process -FilePath 'C:/Program Files/MATLAB/R2025b/bin/matlab.exe' -ArgumentList @('-singleCompThread','-batch',('"'+$fixExpression+'"'),'-logfile',('"'+$fixLog+'"')) -WindowStyle Hidden -Wait -PassThru
    Set-Content -LiteralPath "output/retest-6f1fd6d-20261023_162307/matlab-group-$fixGroup-exit.txt" -Value $fixProcess.ExitCode
    Get-Content -LiteralPath $fixLog -Tail 5
    if($fixProcess.ExitCode -ne 0){exit $fixProcess.ExitCode}
}
Write-Output 'ALL_SOFTWARE_GROUPS_PASS'

