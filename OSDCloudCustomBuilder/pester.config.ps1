# pester.config.ps1
$config = New-PesterConfiguration
$config.Run.Path = './Tests'
$config.Run.Exit = $true
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = './TestResults.xml'
$config.Output.Verbosity = 'Detailed'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './Private', './Public'
$config.CodeCoverage.OutputPath = './CodeCoverage.xml'
$config.CodeCoverage.OutputFormat = 'JaCoCo'

return $config