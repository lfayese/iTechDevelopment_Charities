FROM mcr.microsoft.com/devcontainers/base:jammy

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /workspace
ENV SHELL=/bin/bash

# Install common tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential curl wget unzip ca-certificates apt-transport-https \
      software-properties-common gnupg git python3 python3-pip nodejs npm \
      doxygen graphviz shellcheck jq zip vim nano && \
    rm -rf /var/lib/apt/lists/*

# Install .NET SDK & PowerShell
RUN wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y dotnet-sdk-8.0 powershell && \
    rm -rf /var/lib/apt/lists/*

# Add symlink for pwsh
RUN ln -s /usr/bin/pwsh /usr/bin/powershell

# Install PowerShell Modules
RUN pwsh -Command "\
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force; \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Install-Module Pester,PSScriptAnalyzer,platyPS,InvokeBuild,PowerShellGet,PSDepend,PSModuleDevelopment,ImportExcel,PowerShellProTools,OSD -Force -AllowClobber;"

# Install AI tools (Python + Node + TabNine)
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3-openai && \
    npm install -g bito-cli @bitoai/bito chatgpt-cli openai-cli gpt-cli @githubnext/github-copilot-cli && \
    pip3 install openai chatgpt-wrapper && \
    rm -rf /var/lib/apt/lists/*

# Install TabNine
RUN mkdir -p /opt/tabnine && cd /opt/tabnine && \
    wget -q https://update.tabnine.com/bundles/version -O version && \
    VERSION=$(cat version) && \
    wget -q https://update.tabnine.com/bundles/$VERSION/x86_64-unknown-linux-musl/TabNine.zip && \
    unzip TabNine.zip && rm TabNine.zip version && \
    ln -s /opt/tabnine/TabNine /usr/local/bin/tabnine && \
    mkdir -p /root/.config/TabNine && \
    echo '{\"version\":{\"semver\":\"\",\"nightly\":{\"date\":\"\",\"hash\":\"\"},\"beta\":\"\",\"timestamp\":\"\"},\"update_method\":\"AutoUpdate\"}' > /root/.config/TabNine/tabnine_config.json

# Create PowerShell Profile
RUN mkdir -p /root/.config/powershell && \
    echo '# PowerShell Profile for module development' > /root/.config/powershell/Microsoft.PowerShell_profile.ps1 && \
    pwsh -Command "Add-Content -Path /root/.config/powershell/Microsoft.PowerShell_profile.ps1 -Value @'
Import-Module PSScriptAnalyzer
Import-Module OSD
function Start-ModuleTest { Invoke-Pester }
function Start-ScriptAnalysis { Invoke-ScriptAnalyzer -Path . -Recurse }
function New-ModuleDoc { New-MarkdownHelp -Module $args[0] -OutputFolder \"docs\" }
function Invoke-BitoAI { param([Parameter(ValueFromPipeline=$true)]$code) process { if ($code) { echo $code | bito } else { bito } } }
function Invoke-ChatGPT { param([string]$prompt) chatgpt \"$prompt\" }
function Get-AIExplanation { param([Parameter(ValueFromPipeline=$true)]$code) process { if ($code) { echo $code | bito explain } else { Write-Host \"Please pipe code to this function\" } } }
function Invoke-TabNine { param([string]$query) tabnine --message \"Predict: $query\" }
function Start-TabNineServer { tabnine-serve }
if (-not (Get-Process -Name \"TabNine\" -ErrorAction SilentlyContinue)) {
    Start-Process -NoNewWindow -FilePath \"tabnine\" -ArgumentList \"--client=powershell\", \"serve\"
}
Write-Host \"PowerShell Module Development Environment with AI Tools Ready\" -ForegroundColor Green
'@"

# Create helper scripts
RUN echo '#!/bin/bash
if [ -p /dev/stdin ]; then cat | bito "$@"; else bito "$@"; fi' > /usr/local/bin/ai-helper && \
    chmod +x /usr/local/bin/ai-helper && \
    echo '#!/bin/bash
if [ -p /dev/stdin ]; then cat | github-copilot-cli "$@"; else github-copilot-cli "$@"; fi' > /usr/local/bin/copilot-helper && \
    chmod +x /usr/local/bin/copilot-helper && \
    echo '#!/bin/bash
tabnine --message "Predict: $*"' > /usr/local/bin/tab-complete && \
    chmod +x /usr/local/bin/tab-complete

# Final cleanup
RUN apt-get autoremove -y && apt-get clean -y