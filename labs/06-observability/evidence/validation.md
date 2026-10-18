# Validação do Lab 06

Data: 18/10/2026 17:17 (America/Sao_Paulo)

## Ambiente

- PostgreSQL 16 com Patroni 4.1.0 e dois membros
- etcd 3.5.21 com três membros
- PostgreSQL Exporter 0.17.1
- Prometheus 3.1.0
- Grafana 11.4.0
- Loki e Promtail 3.3.2
- execução local com Docker Compose

## Procedimento

```bash
docker compose build
docker compose up -d --wait --wait-timeout 300
bash scripts/check.sh
```

## Resultado

O check automatizado foi concluído com sucesso e confirmou:

- 100 clientes e 500 pedidos na base `appdb`;
- endpoint do HAProxy conectado ao líder;
- uma réplica em streaming;
- dois exporters PostgreSQL disponíveis no Prometheus;
- exatamente um líder observado pela métrica `patroni_primary`;
- regras `PostgreSQLExporterDown`, `PatroniLeaderMissing` e `ReplicationLagHigh` carregadas;
- Loki e Grafana saudáveis;
- dashboard `postgresql-reliability-overview` provisionado;
- consulta de 350 ms registrada em JSON pelo PostgreSQL, coletada pelo Promtail e encontrada no Loki pelo token `observability_check_1792354677_19734`.

Horário UTC registrado pelo script: `2026-10-18T20:17:56Z` a `2026-10-18T20:17:59Z`.

Esta execução comprova o caminho básico de telemetria no ambiente local. Não valida retenção, entrega de notificações, comportamento sob carga prolongada nem disponibilidade dos próprios componentes de observabilidade.
