FROM mcr.microsoft.com/powershell:7.5.0-ubuntu-22.04
# Set labels for better container management
LABEL maintainer="iTechDevelopment_Charities" \
      description="Development environment for OSDCloudCustomBuilder" \
      version="1.0"
# Set environment variable to prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive
# Install Git and other essential tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
         git \
         curl \
         wget \
         unzip \
         tar \
         procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
# Install PowerShell modules needed for OSDCloudCustomBuilder development
RUN pwsh -Command "\
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Install-Module Pester -Force -MinimumVersion 5.3.0; \
    Install-Module PSScriptAnalyzer -Force; \
    Install-Module ThreadJob -Force; \
    Install-Module OSD -Force; \
    Install-Module ImportExcel -Force"
# Create development workspace directory
WORKDIR /workspace
# Set PowerShell as the default shell
SHELL ["pwsh", "-Command"]