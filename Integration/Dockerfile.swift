FROM swift:6.2.4-noble
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /swifttrial
COPY IntegrationClient/ ./
# Dependency downloads occur only while building, before private trial runtime.
RUN swift --version > /swifttrial/swift-version.txt && swift package resolve
RUN swift test -j 2 2>&1 | tee /swifttrial/unit-tests.log
RUN swift build -j 2 --product IntegrationTrialCLI
USER 10001:10001
CMD ["/swifttrial/.build/debug/IntegrationTrialCLI"]
