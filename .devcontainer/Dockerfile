FROM mcr.microsoft.com/devcontainers/base:jammy

# Update and install common development tools and dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    build-essential \
    curl \
    wget \
    unzip \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    gnupg \
    git \
    python3 \
    python3-pip \
    nodejs \
    npm

# Install .NET SDK (useful for PowerShell module development)
RUN wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y dotnet-sdk-9.0

# Install PowerShell 7
RUN curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -o packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y powershell \
    && rm packages-microsoft-prod.deb

# Create a symbolic link for easier access
RUN ln -s /usr/bin/pwsh /usr/bin/powershell

# Install PowerShell module development tools
RUN pwsh -Command " \
    # Install NuGet Provider \
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force; \
    # Set PSGallery as trusted repository \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    # Install Pester for testing \
    Install-Module -Name Pester -Force -SkipPublisherCheck; \
    # Install PSScriptAnalyzer for code linting \
    Install-Module -Name PSScriptAnalyzer -Force; \
    # Install platyPS for documentation generation \
    Install-Module -Name platyPS -Force; \
    # Install InvokeBuild for build automation \
    Install-Module -Name InvokeBuild -Force; \
    # Install PowerShellGet for publishing modules \
    Install-Module -Name PowerShellGet -Force -AllowClobber; \
    # Install PSDepend for dependency management \
    Install-Module -Name PSDepend -Force; \
    # Install PSModuleDevelopment for module scaffolding \
    Install-Module -Name PSModuleDevelopment -Force; \
    # Install ImportExcel for Excel integration \
    Install-Module -Name ImportExcel -Force; \
    # Install OSD Module for OS deployment utilities \
    Install-Module -Name OSD -Force"

# Install Bito AI and ChatGPT tools
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    python3-openai \
    && npm install -g bito-cli @bitoai/bito \
    && npm install -g chatgpt-cli openai-cli gpt-cli \
    && pip3 install openai chatgpt-wrapper

# Install TabNine AI
RUN mkdir -p /opt/tabnine && cd /opt/tabnine \
    && wget -q https://update.tabnine.com/bundles/version -O version \
    && VERSION=$(cat version) \
    && wget -q https://update.tabnine.com/bundles/$VERSION/x86_64-unknown-linux-musl/TabNine.zip \
    && unzip TabNine.zip && rm TabNine.zip version \
    && ln -s /opt/tabnine/TabNine /usr/local/bin/tabnine \
    && mkdir -p /root/.config/TabNine \
    && echo '{"version":{"semver":"","nightly":{"date":"","hash":""},"beta":"","timestamp":""},"update_method":"AutoUpdate"}' > /root/.config/TabNine/tabnine_config.json

# Install additional development tools
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    doxygen \
    graphviz \
    shellcheck \
    jq \
    zip \
    vim \
    nano

# Clean up
RUN apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Set up PowerShell profile with useful defaults
RUN mkdir -p /root/.config/powershell \
    && echo '# PowerShell Profile for module development\n\
Import-Module PSScriptAnalyzer\n\
Import-Module OSD\n\
function Start-ModuleTest { Invoke-Pester }\n\
function Start-ScriptAnalysis { Invoke-ScriptAnalyzer -Path . -Recurse }\n\
function New-ModuleDoc { New-MarkdownHelp -Module $args[0] -OutputFolder "docs" }\n\
\n\
# AI Development Helpers\n\
function Invoke-BitoAI { param([Parameter(ValueFromPipeline=$true)]$code) process { if ($code) { echo $code | bito } else { bito } } }\n\
function Invoke-ChatGPT { param([string]$prompt) chatgpt "$prompt" }\n\
function Get-AIExplanation { param([Parameter(ValueFromPipeline=$true)]$code) process { if ($code) { echo $code | bito explain } else { Write-Host "Please pipe code to this function" } } }\n\
function Invoke-TabNine { param([string]$query) tabnine --message "Predict: $query" }\n\
function Start-TabNineServer { tabnine-serve }\n\
\n\
# Setup TabNine if not running\n\
if (-not (Get-Process -Name "TabNine" -ErrorAction SilentlyContinue)) {\n\
    Start-Process -NoNewWindow -FilePath "tabnine" -ArgumentList "--client=powershell", "serve"\n\
}\n\
\n\
Write-Host "PowerShell Module Development Environment with AI Tools Ready" -ForegroundColor Green' > /root/.config/powershell/Microsoft.PowerShell_profile.ps1

# Create AI helper scripts
RUN mkdir -p /usr/local/bin \
    && echo '#!/bin/bash\n\
if [ -p /dev/stdin ]; then\n\
    # If we have something on stdin, use it\n\
    cat | bito "$@"\n\
else\n\
    # Otherwise, just run bito with any arguments passed\n\
    bito "$@"\n\
fi' > /usr/local/bin/ai-helper \
    && chmod +x /usr/local/bin/ai-helper

# Create TabNine helper for terminal use
RUN echo '#!/bin/bash\n\
tabnine --message "Predict: $*"' > /usr/local/bin/tab-complete \
    && chmod +x /usr/local/bin/tab-complete

# Set environment variables
ENV SHELL=/bin/bash

# Set working directory
WORKDIR /workspace
