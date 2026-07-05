<#
.SYNOPSIS
  Confirm GLM-5.2 reasoning-effort controls actually reach Z.AI when routed
  through the team's LiteLLM proxy, and check whether Hermes's own
  agent.reasoning_effort plumbing survives the trip intact.

.DESCRIPTION
  This does NOT touch the running hermes-agent container — it makes plain
  HTTPS chat-completion calls with curl-equivalent bodies, once straight to
  Z.AI and once through the LiteLLM proxy, and diffs the results. Three
  question groups:

  1. Proxy transparency: for the SAME correctly-shaped Z.AI payload
     (`thinking: {type: ...}` + `reasoning_effort: ...`, per
     https://docs.z.ai/api-reference/llm/chat-completion), does the proxied
     call behave the same as the direct-to-Z.AI call (reasoning_content
     present/absent, roughly comparable length)? If not, LiteLLM itself is
     dropping or rewriting the param (see drop_params /
     allowed_openai_params in LiteLLM's docs).

  2. Hermes-shaped payload: Hermes's `zai` provider currently sends
     `extra_body.reasoning = {enabled, effort}` (OpenRouter convention), NOT
     `extra_body.thinking` (see NousResearch/hermes-agent#16533, still open
     as of 2026-07 with fix PR #16592 unmerged). This sends that exact
     shape through the proxy to see whether Z.AI silently ignores it in
     THIS environment, reproducing the bug end-to-end rather than trusting
     the issue report.

  3. Baseline delta: reasoning-enabled/high vs. disabled, same path, to
     confirm the model's behavior actually changes with the setting at all
     (sanity check that "enabled" isn't a no-op for unrelated reasons).

  Requires env vars (loaded from .env in repo root if present, otherwise
  must already be set): Z_AI_API_KEY, GLM_API_KEY, GLM_BASE_URL.

  Cost note: 5 short, non-streaming chat completions (small prompt, low
  max_tokens) against the real Z.AI account and the shared LiteLLM proxy —
  trivial against the team's Coding Plan budget, but it IS real spend
  against the shared pool documented in config/config.yaml, not a mock.

  Exit codes: 0 = proxy transparency confirmed, 1 = proxy passthrough
  mismatch detected, 2 = setup error (missing keys/tools).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $RootDir '.env'

function Fail-Setup([string]$msg) { Write-Host $msg -ForegroundColor Red; exit 2 }

# --- Load .env (only fills vars not already set in the environment) -------
if (Test-Path $EnvFile) {
  Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$') {
      $name = $Matches[1]; $value = $Matches[2]
      if (-not (Get-Item "Env:$name" -ErrorAction SilentlyContinue)) {
        Set-Item "Env:$name" $value
      }
    }
  }
}

foreach ($v in @('Z_AI_API_KEY', 'GLM_API_KEY', 'GLM_BASE_URL')) {
  if (-not (Get-Item "Env:$v" -ErrorAction SilentlyContinue) -or [string]::IsNullOrWhiteSpace((Get-Item "Env:$v").Value)) {
    Fail-Setup "error: `$env:$v is not set (checked process env and $EnvFile)."
  }
}

$DirectUrl = 'https://api.z.ai/api/paas/v4/chat/completions'
$ProxyUrl  = ($env:GLM_BASE_URL.TrimEnd('/')) + '/chat/completions'
$Model     = 'glm-5.2'

# A prompt with a checkable multi-step answer, cheap enough to keep max_tokens low.
$Prompt = 'A train leaves at 2:15pm and travels 3 legs: 45 min, then a 20 min stop, then 1hr 10min. What time does it arrive? Answer with just the final HH:MM.'

function Invoke-ChatCompletion {
  param(
    [string]$Name,
    [string]$Url,
    [string]$ApiKey,
    [hashtable]$ExtraBody
  )

  $body = @{
    model       = $Model
    messages    = @(@{ role = 'user'; content = $Prompt })
    max_tokens  = 300
    temperature = 0
  }
  foreach ($k in $ExtraBody.Keys) { $body[$k] = $ExtraBody[$k] }

  $headers = @{ Authorization = "Bearer $ApiKey"; 'Content-Type' = 'application/json' }
  $json = $body | ConvertTo-Json -Depth 6

  $result = [ordered]@{
    name             = $Name
    ok               = $false
    reasoning_len    = 0
    completion_toks  = $null
    content_snippet  = ''
    error            = $null
  }

  try {
    $resp = Invoke-RestMethod -Uri $Url -Method Post -Headers $headers -Body $json -TimeoutSec 60
    $msg = $resp.choices[0].message
    $result.ok = $true
    $result.reasoning_len   = if ($msg.reasoning_content) { $msg.reasoning_content.Length } else { 0 }
    $result.completion_toks = $resp.usage.completion_tokens
    $result.content_snippet = ($msg.content -replace '\s+', ' ').Substring(0, [Math]::Min(60, ($msg.content -replace '\s+',' ').Length))
  } catch {
    $result.error = $_.Exception.Message
  }
  return [pscustomobject]$result
}

Write-Host "Direct Z.AI endpoint : $DirectUrl"
Write-Host "LiteLLM proxy endpoint: $ProxyUrl"
Write-Host "Model                : $Model"
Write-Host ''

$cases = @(
  @{ Name = 'direct-disabled';        Url = $DirectUrl; Key = $env:Z_AI_API_KEY; Body = @{ thinking = @{ type = 'disabled' } } }
  @{ Name = 'direct-enabled-high';    Url = $DirectUrl; Key = $env:Z_AI_API_KEY; Body = @{ thinking = @{ type = 'enabled' }; reasoning_effort = 'high' } }
  @{ Name = 'proxy-disabled';         Url = $ProxyUrl;  Key = $env:GLM_API_KEY; Body = @{ thinking = @{ type = 'disabled' } } }
  @{ Name = 'proxy-enabled-high';     Url = $ProxyUrl;  Key = $env:GLM_API_KEY; Body = @{ thinking = @{ type = 'enabled' }; reasoning_effort = 'high' } }
  @{ Name = 'proxy-hermes-shaped';    Url = $ProxyUrl;  Key = $env:GLM_API_KEY; Body = @{ reasoning = @{ enabled = $true; effort = 'medium' } } }
)

$results = @()
foreach ($c in $cases) {
  Write-Host "-> $($c.Name) ..." -NoNewline
  $r = Invoke-ChatCompletion -Name $c.Name -Url $c.Url -ApiKey $c.Key -ExtraBody $c.Body
  $results += $r
  if ($r.ok) { Write-Host " done (reasoning_content len=$($r.reasoning_len), completion_tokens=$($r.completion_toks))" }
  else { Write-Host " ERROR: $($r.error)" -ForegroundColor Red }
}

Write-Host ''
$results | Format-Table name, ok, reasoning_len, completion_toks, content_snippet -AutoSize

$byName = @{}
foreach ($r in $results) { $byName[$r.name] = $r }

Write-Host ''
Write-Host '--- Verdicts ---'

$verdictExit = 0

# Verdict 1: proxy transparency for correctly-shaped payloads.
$dDisabled = $byName['direct-disabled']; $pDisabled = $byName['proxy-disabled']
$dEnabled  = $byName['direct-enabled-high']; $pEnabled  = $byName['proxy-enabled-high']
if ($dDisabled.ok -and $pDisabled.ok -and $dEnabled.ok -and $pEnabled.ok) {
  $disabledMatch = ($dDisabled.reasoning_len -eq 0) -eq ($pDisabled.reasoning_len -eq 0)
  $enabledMatch  = ($dEnabled.reasoning_len -gt 0)  -eq ($pEnabled.reasoning_len -gt 0)
  if ($disabledMatch -and $enabledMatch) {
    Write-Host "PASS: LiteLLM proxy passes thinking/reasoning_effort through unmodified (proxied behavior matches direct Z.AI for both disabled and enabled-high)." -ForegroundColor Green
  } else {
    Write-Host "FAIL: proxy behavior diverges from direct Z.AI for an identical payload -> LiteLLM is altering/dropping thinking/reasoning_effort." -ForegroundColor Red
    $verdictExit = 1
  }
} else {
  Write-Host "SKIP verdict 1: one or more calls errored, see table above." -ForegroundColor Yellow
  $verdictExit = 1
}

# Verdict 2: does the direct/proxy enabled-high call actually change behavior vs disabled (sanity check the knob does something)?
if ($pDisabled.ok -and $pEnabled.ok) {
  if ($pEnabled.reasoning_len -gt 0 -and $pDisabled.reasoning_len -eq 0) {
    Write-Host "OK: reasoning_effort visibly changes proxied model behavior (disabled -> no reasoning_content, high -> reasoning_content present)." -ForegroundColor Green
  } else {
    Write-Host "NOTE: disabled vs enabled-high did not show the expected reasoning_content on/off difference via the proxy — investigate before trusting the knob." -ForegroundColor Yellow
  }
}

# Verdict 3: reproduce (or clear) the known Hermes payload-shape bug (NousResearch/hermes-agent#16533).
$pHermes = $byName['proxy-hermes-shaped']
if ($pHermes.ok) {
  if ($pHermes.reasoning_len -eq 0) {
    Write-Host "CONFIRMED BUG (matches hermes-agent#16533, PR #16592 still unmerged): the payload shape Hermes's zai provider actually sends today (extra_body.reasoning) produces NO reasoning_content via this proxy -> setting agent.reasoning_effort in a profile's config.yaml currently has no effect on Z.AI/GLM." -ForegroundColor Red
  } else {
    Write-Host "Hermes-shaped payload DID produce reasoning_content here — hermes-agent#16533 may be fixed/mitigated in the running image version, or the proxy is normalizing the field. Worth re-checking against the actual image tag in use." -ForegroundColor Yellow
  }
} else {
  Write-Host "SKIP verdict 3: proxy-hermes-shaped call errored, see table above." -ForegroundColor Yellow
}

exit $verdictExit
