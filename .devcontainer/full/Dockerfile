# Layers on top of the published base image to bake in the npm-dependent CLI
# installs that postCreateCommand previously had to defer until npm existed
# (npm is provided by the node Feature baked into the base image).
# Built & published by .github/workflows/publish-full-image.yml to:
#   ghcr.io/bugrasan/devcontainer-base-ai/full:latest
# which the root ../../devcontainer.json then consumes via its "image" property
# (see .devcontainer/full/devcontainer.json for the build definition, which adds
# the sshd Feature on top of this Dockerfile).
FROM ghcr.io/bugrasan/devcontainer-base-ai/base:latest

# Same global npm packages previously installed via postCreateCommand's 'npm-packages' step.
RUN npm install -g editorconfig eslint typescript @mermaid-js/mermaid-cli

# anthropic claude code cli - https://code.claude.com/docs/en/overview
RUN curl -fsSL https://claude.ai/install.sh | bash

# pi.dev cli
RUN curl -fsSL https://pi.dev/install.sh | sh

CMD ["bash"]
