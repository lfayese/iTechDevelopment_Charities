# OSDCloudCustomBuilder Specialized Test Suite

This directory contains specialized tests for the OSDCloudCustomBuilder module focusing on:

1. **Security Testing**
   - Path validation with special characters and traversal attempts
   - Handling of filenames with spaces or quotes
   - Privilege enforcement for admin-required operations

2. **Performance Testing**
   - Parallel file operations with large numbers of files
   - Optimized string handling
   - Cancellation of long-running operations

3. **Error Handling Testing**
   - Simulation of various error conditions to verify consistent handling
   - Testing with non-existent files and paths
   - Verification of proper error propagation and logging

4. **Logging Testing**
   - Verification that log entries contain all required metadata
   - Testing concurrent logging from multiple threads
   - Checking fallback mechanisms when primary logging fails

## Running the Tests

You can run the specialized tests using the `Run-SpecializedTests.ps1` script:

```powershell
# Run all specialized tests
.\Run-SpecializedTests.ps1

# Run only security tests
.\Run-SpecializedTests.ps1 -Categories Security

# Run performance and error handling tests with detailed output
.\Run-SpecializedTests.ps1 -Categories Performance, ErrorHandling -Verbosity Detailed

# Generate an HTML report
.\Run-SpecializedTests.ps1 -GenerateReport
```

## Test Categories

### Security Tests

Located in the `Security` folder, these tests verify that the module properly handles:
- Path validation and normalization
- Protection against path traversal attacks
- Secure process execution with proper parameter escaping
- Administrative privilege verification

### Performance Tests

Located in the `Performance` folder, these tests measure and verify:
- Efficient parallel processing of file operations
- Optimized string handling
- Support for cancellation of long-running operations

### Error Handling Tests

Located in the `ErrorHandling` folder, these tests verify:
- Consistent handling of various error types
- Proper error context and details
- Error propagation through the call stack
- Retry logic for transient failures

### Logging Tests

Located in the `Logging` folder, these tests verify:
- Log entry metadata completeness
- Thread-safe concurrent logging
- Fallback mechanisms when primary logging fails
- Log level filtering and component filtering

## Integration with Main Test Suite

These specialized tests complement the main test suite and can be run independently or as part of the comprehensive testing process. The `Comprehensive-TestSuite.Tests.ps1` file provides a way to run all specialized tests together.

## Requirements

- Pester 5.0 or higher
- PowerShell 5.1 or higher (PowerShell 7+ recommended for parallel tests)
- ReportGenerator (optional, for HTML reports)