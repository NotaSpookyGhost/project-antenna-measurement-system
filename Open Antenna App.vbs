Option Explicit

' Double-click to open the antenna GUI using the installed MATLAB.
Dim shell, files, projectDir, matlabExe, entry, command, matlabCode, logDir, runtimeLog, stamp
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
projectDir = files.GetParentFolderName(WScript.ScriptFullName)
matlabExe = shell.ExpandEnvironmentStrings("%ProgramFiles%") & "\MATLAB\R2025b\bin\matlab.exe"

If Not files.FileExists(matlabExe) Then
    matlabExe = ""
    For Each entry In Split(shell.ExpandEnvironmentStrings("%PATH%"), ";")
        entry = Replace(Trim(entry), Chr(34), "")
        If Len(entry) > 0 Then
            If files.FileExists(files.BuildPath(entry, "matlab.exe")) Then
                matlabExe = files.BuildPath(entry, "matlab.exe")
                Exit For
            End If
        End If
    Next
End If

If Len(matlabExe) = 0 Then
    MsgBox "MATLAB was not found. Install MATLAB R2025b or add matlab.exe to PATH.", vbCritical, "Antenna Measurement"
    WScript.Quit 1
End If

matlabCode = "try; addpath('matlab/classes','matlab/app'); app=AntennaMeasurementApp(); waitfor(app.Figure); exit; catch ME; f=errordlg(ME.message,'Antenna startup error','modal'); waitfor(f); exit(1); end"
logDir = files.BuildPath(projectDir, "data\logs")
If Not files.FolderExists(logDir) Then files.CreateFolder logDir
stamp = Year(Now) & Right("0" & Month(Now), 2) & Right("0" & Day(Now), 2) & "_" & Right("0" & Hour(Now), 2) & Right("0" & Minute(Now), 2) & Right("0" & Second(Now), 2)
runtimeLog = files.BuildPath(logDir, "matlab_runtime_" & stamp & ".txt")
command = Chr(34) & matlabExe & Chr(34) & " -automation -sd " & Chr(34) & projectDir & Chr(34) & " -logfile " & Chr(34) & runtimeLog & Chr(34) & " -r " & Chr(34) & matlabCode & Chr(34)
shell.CurrentDirectory = projectDir
shell.Run command, 0, False
