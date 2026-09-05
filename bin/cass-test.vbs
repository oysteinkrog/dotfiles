Dim fso
Set fso = CreateObject("Scripting.FileSystemObject")
Dim f
Set f = fso.OpenTextFile("C:\Users\Oystein\bin\cass-maintenance-launcher.log", 8, True)
f.WriteLine "test ran at " & Now
f.Close
WScript.Quit 0
