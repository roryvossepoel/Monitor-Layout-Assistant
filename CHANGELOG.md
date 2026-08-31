# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.0] - 2026-08-31

### Added

- Initial English Monitor Layout Assistant interface.
- Automatic horizontal display arrangement.
- External primary-display selection.
- Configurable MultiMonitorTool path.
- Installer with optional `powershellw.exe` detection.
- Uninstaller and third-party dependency documentation.
- Language selection through separate JSON language files with English fallback.
- English, Dutch, German, French, Spanish, Italian and Portuguese translations.
- Language selection through `config.json`.
- Application icon for the interface and Start menu shortcut.
- Persistent per-user logging with consistent severity levels and log rotation.
- Installer warning when the optional hidden PowerShell host is unavailable.
- Structured interface theme in `config.json`, including configurable choice-button borders.
- Precisely aligned vector choice arrows and a configurable neutral information panel.
- Dedicated Windows taskbar identity so the application icon can be used instead of the PowerShell host icon.
- Application files grouped in the `App` directory with a ready-to-use `config.json`.