# Dev helper: emit a seed-state JSON for seed_state.ps1.
# Scenarios: reveal | midsession | break | map | journey | notify
param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [int]$Sets = 0,
    [int]$Level = 1,
    [string]$Theme = "system"
)

$now = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
$min = 60000

function BaseState {
    param([hashtable]$Overrides)
    $state = [ordered]@{
        xpIntoLevel = 0; level = $script:Level; stamina = 100.0
        lifetimeKm = 0.0; totalFocusSeconds = 0; sessionsCompleted = 0
        setsCompleted = $script:Sets; sessionIndexInSet = 0
        badgeIds = @(); dailyFocusMinutes = @{}
        timer = [ordered]@{
            phase = 'idle'; breakKind = $null; segmentStartedAtMs = $null
            phaseEndsAtMs = $null; accumulatedFocusMs = 0; bankedDistanceKm = 0.0
            staminaAtSessionStart = 100.0; levelAtSessionStart = $script:Level
            staminaAtBreakStart = 100.0
        }
        pendingReveal = $null
        settings = [ordered]@{
            theme = $script:Theme; notificationsEnabled = $true
        }
    }
    foreach ($k in $Overrides.Keys) { $state[$k] = $Overrides[$k] }
    return $state
}

$state = switch ($Scenario) {
    'reveal' {
        # Focus session that ended 5 minutes ago while "dead"; level 9 → 10.
        $s = BaseState @{ level = 9; xpIntoLevel = 25 }
        $s.timer.phase = 'focusRunning'
        $s.timer.segmentStartedAtMs = $now - 30 * $min
        $s.timer.phaseEndsAtMs = $now - 5 * $min
        $s.timer.levelAtSessionStart = 9
        $s
    }
    'midsession' {
        $s = BaseState @{}
        $s.timer.phase = 'focusRunning'
        $s.timer.segmentStartedAtMs = $now - 5 * $min
        $s.timer.phaseEndsAtMs = $now + 20 * $min
        $s
    }
    'break' {
        $s = BaseState @{ stamina = 75.0; sessionsCompleted = 1; sessionIndexInSet = 1 }
        $s.timer.phase = 'breakRunning'
        $s.timer.breakKind = 'short'
        $s.timer.segmentStartedAtMs = $now - 1 * $min
        $s.timer.phaseEndsAtMs = $now + 4 * $min
        $s.timer.staminaAtBreakStart = 75.0
        $s
    }
    'map' { BaseState @{} }
    'journey' {
        $daily = [ordered]@{}
        for ($i = 13; $i -ge 0; $i--) {
            $d = (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd')
            $daily[$d] = @(0, 25, 50, 75, 100, 125)[(Get-Random -Maximum 6)]
        }
        BaseState @{
            level = 22; xpIntoLevel = 40; lifetimeKm = 850.0
            totalFocusSeconds = 166500; sessionsCompleted = 111; sessionIndexInSet = 3
            badgeIds = @('tier-10', 'tier-20', 'cmp-walking-human', 'odo-5',
                'odo-10', 'odo-21', 'odo-42', 'odo-100', 'odo-800', 'map-1')
            dailyFocusMinutes = $daily
        }
    }
    'notify' {
        $s = BaseState @{}
        $s.timer.phase = 'focusRunning'
        $s.timer.segmentStartedAtMs = $now - 1 * $min
        $s.timer.phaseEndsAtMs = $now + 75000
        $s
    }
    default { throw "unknown scenario $Scenario" }
}

$doc = [ordered]@{ schemaVersion = 1; state = $state }
$doc | ConvertTo-Json -Depth 8 -Compress
