' cass-maintenance.vbs — hidden launcher for the cass maintenance script.
'
' Triggered by Task Scheduler via wscript.exe. Runs wsl.exe with window
' style 0 (hidden), waits for completion, and propagates the exit code
' so Task Scheduler records the real success/failure of the bash script.
'
' Why VBS: powershell.exe -WindowStyle Hidden still flashes wsl.exe's
' console briefly. wscript.exe + Run(..., 0, True) is the standard
' Windows "truly hidden" pattern.
'
' Wrapper-level errors (e.g. wsl.exe missing, distro not started) are
' captured in launcher.log next to the script; the bash script writes
' its own detailed log to ~/.local/share/cass-maintenance.log.

Dim wsh, fso, logPath, logFile, rc, startedAt

Set wsh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

logPath = "C:\Users\Oystein\bin\cass-maintenance-launcher.log"
startedAt = Now

' Use cmd.exe to run wsl and capture stderr/stdout to the launcher log,
' so any wsl-level failure (distro not running, invalid path, etc.) is
' visible. The bash script does its own internal logging afterward.
Dim cmd
cmd = "cmd.exe /d /c """ & _
      "wsl.exe bash /c/users/oystein/.local/bin/cass-maintenance.sh" & _
      " >> """ & logPath & """ 2>&1" & _
      """"

' Append a header for this invocation.
On Error Resume Next
Set logFile = fso.OpenTextFile(logPath, 8, True)  ' 8=ForAppending, True=create
If Not logFile Is Nothing Then
  logFile.WriteLine "===== " & startedAt & " launcher start (pid=" & wsh.Environment("PROCESS").Item("PROCESS_ID") & ") ====="
  logFile.Close
End If
On Error Goto 0

rc = wsh.Run(cmd, 0, True)

On Error Resume Next
Set logFile = fso.OpenTextFile(logPath, 8, True)
If Not logFile Is Nothing Then
  logFile.WriteLine "===== " & Now & " launcher done rc=" & rc & " ====="
  logFile.Close
End If
On Error Goto 0

WScript.Quit rc
