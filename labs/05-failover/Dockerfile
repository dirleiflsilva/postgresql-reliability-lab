FROM postgres:16-bookworm
ARG PATRONI_VERSION=4.1.0
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv curl \
    && python3 -m venv /opt/patroni \
    && /opt/patroni/bin/pip install --no-cache-dir "patroni[etcd3,psycopg3]==${PATRONI_VERSION}" \
    && rm -rf /var/lib/apt/lists/*
ENV PATH="/opt/patroni/bin:${PATH}"
COPY config/patroni.yml /etc/patroni.yml
COPY init /lab/init
COPY scripts/bootstrap.sh scripts/entrypoint.sh /lab/
RUN chmod +x /lab/*.sh
ENTRYPOINT ["/lab/entrypoint.sh"]
CMD ["patroni", "/etc/patroni.yml"]
