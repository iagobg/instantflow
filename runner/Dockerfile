# Supply a reviewed ARM64-compatible base digest. No unpinned default.
ARG PYTHON_BASE
FROM ${PYTHON_BASE}
COPY execute.py /opt/runner.py
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/python3", "-I", "-B", "/opt/runner.py"]
