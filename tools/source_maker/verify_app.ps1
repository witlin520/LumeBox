$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '../..')
try {
    $bridgePresent = @('Debug', 'Release', 'Profile') | Where-Object {
        Test-Path -LiteralPath "build/windows/x64/runner/$_/quickjs_c_bridge_plugin.dll"
    }
    if (-not $bridgePresent) { throw 'Build the Windows QuickJS bridge before running App contract checks' }
    python tools/source_maker/make_fixtures.py build/source-maker-fixtures
    if ($LASTEXITCODE -ne 0) { throw 'Export generation failed' }
    python tools/source_maker/check_python_host.py build/source-maker-fixtures
    if ($LASTEXITCODE -ne 0) { throw 'Production Python host check failed' }
    flutter test --no-pub test/source_maker_contract_test.dart test/source_packages_test.dart test/kazumi_rule_test.dart test/cat_local_bundle_test.dart test/web_home_sources_test.dart --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'App contract checks failed' }
} finally {
    Pop-Location
}
