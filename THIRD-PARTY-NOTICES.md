# Third-party software

Monitor Layout Assistant does not include third-party binaries. Administrators must obtain, assess, and deploy external software according to their own security and compliance requirements.

## MultiMonitorTool

Monitor Layout Assistant requires **MultiMonitorTool.exe** to read and configure the Windows display layout.

- Author: Nir Sofer
- Website: https://www.nirsoft.net/utils/multi_monitor_tool.html
- Requirement: Mandatory
- Included: No

MultiMonitorTool is freeware with its own distribution conditions. Review the current terms published by NirSoft before using or redistributing it.

## RunHiddenConsole

[RunHiddenConsole](https://github.com/SeidChr/RunHiddenConsole) can optionally be installed as `powershellw.exe` to start the application without displaying a PowerShell console window.

- Author: SeidChr
- License: MPL-2.0
- Requirement: Optional
- Included: No

The recommended location for Windows PowerShell 5.1 is:

```text
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershellw.exe
```

If this file is absent, the installer uses the native `powershell.exe`. The application remains fully functional, but its console window stays visible while it is running.

