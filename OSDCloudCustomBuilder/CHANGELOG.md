# CHANGELOG

## [Unreleased] - PowerShell Module Fixes (Applied on 2025-04-01)

### 🛠 Manifest & Versioning

- Synced `ModuleVersion` in `.psd1` and `.psm1` to `0.3.0`
- Replaced `VariablesToExport = '*'` with `@()` to prevent scope leaks

### 🔐 Security Improvements

- Added TLS enforcement skip logic for PowerShell Core using `$PSEdition`
- Added reusable `Test-IsAdmin` helper in `SharedUtilities.psm1`

### 📜 Public API Enhancements

- Annotated all public functions with `[OutputType([void])]`
- Added `[ValidateNotNullOrEmpty()]` to parameters
- Introduced `$EnableVerboseLogging` check for dynamic verbosity

### 🚀 Performance Considerations

- Logging output now toggleable with `$EnableVerboseLogging`
- Added `Test-IsAdmin` helper for security checks

### 🧪 Testing & CI/CD

- Added GitHub Actions workflow:
  - Runs tests on PR and push to `main`
  - Generates and uploads `CodeCoverage.xml`
