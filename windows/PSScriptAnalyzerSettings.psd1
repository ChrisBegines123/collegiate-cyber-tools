# Lints the Windows scripts against Windows PowerShell 5.1, the version that
# ships on stock Windows Server. Run from this directory with:
#
#   Invoke-ScriptAnalyzer -Path . -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse
@{
    IncludeRules = @(
        'PSUseCompatibleSyntax'
        'PSUseCompatibleCmdlets'
        'PSUseCompatibleCommands'
        'PSUseCompatibleTypes'
    )

    Rules = @{
        # Syntax that doesn't parse on 5.1 (e.g. a pipeline continued with a leading '|').
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }

        # Cmdlets missing on 5.1.
        PSUseCompatibleCmdlets = @{
            compatibility = @('desktop-5.1.14393.206-windows')
        }

        # Cmdlets and parameters missing on 5.1 (e.g. ConvertFrom-SecureString -AsPlainText).
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @('win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
        }

        # .NET types and members missing on .NET Framework (e.g. static RandomNumberGenerator.GetBytes).
        PSUseCompatibleTypes = @{
            Enable         = $true
            TargetProfiles = @('win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
        }
    }
}
