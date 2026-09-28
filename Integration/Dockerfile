FROM postgres:17.6-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv ca-certificates && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/nidaa-python
ENV PATH=/opt/nidaa-python/bin:$PATH
WORKDIR /trial
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY Integration/requirements.txt /trial/Integration/requirements.txt
COPY Integration/requirements-lock.txt /trial/Integration/requirements-lock.txt
RUN pip install --no-cache-dir -r Integration/requirements.txt -c Integration/requirements-lock.txt
COPY SharedRules /trial/SharedRules
COPY Integration /trial/Integration
USER 10001:10001
CMD ["python", "-m", "uvicorn", "Integration.service.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log", "--log-level", "error"]
