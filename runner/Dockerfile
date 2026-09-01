FROM ubuntu:24.04

ARG RUNNER_VERSION="2.317.0"
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    curl jq git dnsutils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m runner

COPY start.sh /start.sh
RUN chmod +x /start.sh

USER runner
WORKDIR /home/runner

RUN mkdir -p actions-runner && cd actions-runner && \
    curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar xzf actions-runner.tar.gz && rm actions-runner.tar.gz && \
    mkdir -p _work

ENTRYPOINT ["/start.sh"]