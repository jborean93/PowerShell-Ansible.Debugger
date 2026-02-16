using namespace System.IO

. ([Path]::Combine($PSScriptRoot, 'common.ps1'))

Describe "Get-AnsibleLaunchConfig" {
    It "Returns default configuration" {
        $config = Get-AnsibleLaunchConfig

        $config | Should -BeOfType string

        {
            $config | ConvertFrom-Json -ErrorAction Stop
        } | Should -Not -Throw
    }

    It "Sets WorkingDirectory" {
        $config = Get-AnsibleLaunchConfig -WorkingDirectory "C:\Test"
        $json = $config | ConvertFrom-Json -ErrorAction Stop

        $json.cwd | Should -Be "C:\Test"
        $json.serverReadyAction.config.cwd | Should -Be "C:\Test"
    }

    It "Sets inventory and limit" {
        $config = Get-AnsibleLaunchConfig -Inventory inventory.ini -Limit web
        $json = $config | ConvertFrom-Json -ErrorAction Stop

        $json.serverReadyAction.config.args | Should -HaveCount 6
        $json.serverReadyAction.config.args[0] | Should -Be "test"
        $json.serverReadyAction.config.args[1] | Should -Be "pwsh-debug"
        $json.serverReadyAction.config.args[2] | Should -Be "--inventory"
        $json.serverReadyAction.config.args[3] | Should -Be "inventory.ini"
        $json.serverReadyAction.config.args[4] | Should -Be "--limit"
        $json.serverReadyAction.config.args[5] | Should -Be "web"
    }

    It "Sets -WaitAtEntry" {
        $config = Get-AnsibleLaunchConfig -WaitAtEntry
        $json = $config | ConvertFrom-Json -ErrorAction Stop

        $json.serverReadyAction.config.args | Should -HaveCount 3
        $json.serverReadyAction.config.args[0] | Should -Be "test"
        $json.serverReadyAction.config.args[1] | Should -Be "pwsh-debug"
        $json.serverReadyAction.config.args[2] | Should -Be "--wait-at-entry"
    }

    It "Sets inventory and limit with additional arguments" {
        $config = Get-AnsibleLaunchConfig -Inventory inventory.ini -Limit web ansible-playbook '-i' inventory.ini --limit web main.yml -vvv
        $json = $config | ConvertFrom-Json -ErrorAction Stop

        $json.serverReadyAction.config.args | Should -HaveCount 13
        $json.serverReadyAction.config.args[0] | Should -Be "test"
        $json.serverReadyAction.config.args[1] | Should -Be "pwsh-debug"
        $json.serverReadyAction.config.args[2] | Should -Be "--inventory"
        $json.serverReadyAction.config.args[3] | Should -Be "inventory.ini"
        $json.serverReadyAction.config.args[4] | Should -Be "--limit"
        $json.serverReadyAction.config.args[5] | Should -Be "web"
        $json.serverReadyAction.config.args[6] | Should -Be "ansible-playbook"
        $json.serverReadyAction.config.args[7] | Should -Be "-i"
        $json.serverReadyAction.config.args[8] | Should -Be "inventory.ini"
        $json.serverReadyAction.config.args[9] | Should -Be "--limit"
        $json.serverReadyAction.config.args[10] | Should -Be "web"
        $json.serverReadyAction.config.args[11] | Should -Be "main.yml"
        $json.serverReadyAction.config.args[12] | Should -Be "-vvv"
    }
}
