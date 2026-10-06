' AutoTranslator helper launcher.
' Windower opens this file with no arguments; it starts at_helper.ps1 without showing any window.
' (windower.execute does not pass command-line arguments to powershell.exe reliably.)
Option Explicit
Dim fso, sh, helperDir, addonDir, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
helperDir = fso.GetParentFolderName(WScript.ScriptFullName)
addonDir = fso.GetParentFolderName(helperDir)
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & _
      helperDir & "\at_helper.ps1"" -AddonDir """ & addonDir & """"
sh.Run cmd, 0, False
