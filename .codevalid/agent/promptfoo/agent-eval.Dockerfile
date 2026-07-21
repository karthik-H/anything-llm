FROM python:3.11-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
ENV PROMPTFOO_DISABLE_TELEMETRY=1 \
    PROMPTFOO_DISABLE_UPDATE=1 \
    PYTHONUNBUFFERED=1 \
    OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=SPAN_ONLY
RUN npm install -g promptfoo@0.121.17 \
    && pip install --no-cache-dir "langchain>=0.3.0" "langchain-openai>=0.2.0" "litellm>=1.0.0"
WORKDIR /workspace
COPY agents/ /workspace/agents/
COPY .codevalid/agent/ /workspace/.codevalid/agent/
RUN pip install --no-cache-dir -r /workspace/agents/requirements.txt
RUN chmod +x /workspace/.codevalid/agent/promptfoo/agent-eval-entrypoint.sh
ENTRYPOINT ["/workspace/.codevalid/agent/promptfoo/agent-eval-entrypoint.sh"]
