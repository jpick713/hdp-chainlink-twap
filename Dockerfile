FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install HDP CLI
RUN curl -fsSL https://raw.githubusercontent.com/HerodotusDev/hdp-cairo/main/install-cli.sh | bash

# Install Scarb
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | bash

# Set environment variables
ENV PATH="/root/.local/bin:${PATH}"
ENV HDP_DRY_RUN_PATH="/root/.local/share/hdp/dry_run_compiled.json"
ENV HDP_SOUND_RUN_PATH="/root/.local/share/hdp/sound_run_compiled.json"

WORKDIR /project

# Entry point script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]