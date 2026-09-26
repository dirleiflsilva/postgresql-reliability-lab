# PostgreSQL Reliability Lab

Laboratório prático de engenharia de banco de dados com foco em confiabilidade, alta disponibilidade e operação em ambientes de produção utilizando PostgreSQL.

## Objetivo

Este projeto tem como objetivo desenvolver, de forma prática e orientada à produção, as competências necessárias para atuar como **PostgreSQL Database Engineer / Data Platform Engineer**.

O foco não está apenas em aprender PostgreSQL, mas em **operar, escalar e garantir a confiabilidade de bancos de dados em cenários reais**, incluindo falhas controladas.

## Abordagem

O projeto é estruturado como um conjunto de **labs executáveis**, onde cada cenário simula um problema real de engenharia:

- Ambientes reproduzíveis com Docker
- Evolução incremental de uma plataforma PostgreSQL
- Simulação de falhas
- Recuperação de desastres
- Validação com evidências, como logs, métricas e testes

Cada lab adiciona uma nova camada de maturidade sobre os anteriores. A base criada nos primeiros labs é reaproveitada nos cenários de backup, replicação, failover, observabilidade, performance e pipelines.

## Estrutura dos Labs

| Status | Lab | Descrição |
|--------|-----|-----------|
| ✅ | 01 - Foundation | Ambiente PostgreSQL single-node com Docker, volume persistente, healthcheck e inicialização básica |
| ✅ | 02 - Database Initialization | Roles, schemas, extensões, modelo de dados e carga inicial representativa |
| ✅ | 03 - Backup & Restore | Backup lógico, backup físico, restore, WAL archiving e recuperação point-in-time |
| ✅ | 04 - Replication | Streaming replication com primary e replica |
| ✅ | [05 - Failover](labs/05-failover/README.md) | Patroni, etcd, HAProxy e failover automático |
| ⏳ | 06 - Observability | Monitoramento com métricas, logs e dashboards |
| ⏳ | 07 - Performance | Análise de queries, índices e otimização |
| ⏳ | 08 - Data Pipeline | Ingestão e processamento de dados |

**Legenda:**

- ✅ Concluído
- 🚧 Em desenvolvimento
- ⏳ Planejado

## Evolução Esperada

O projeto segue uma progressão próxima do ciclo de vida de uma plataforma de dados:

1. Subir uma instância PostgreSQL funcional e reproduzível.
2. Criar uma base minimamente realista com usuários, permissões, schemas, extensões, tabelas e dados.
3. Proteger essa base com estratégias de backup e restore.
4. Replicar os mesmos dados para cenários de alta disponibilidade.
5. Simular falhas e validar recuperação.
6. Observar comportamento operacional com métricas e logs.
7. Otimizar consultas, índices e configurações.
8. Integrar a base com pipelines de ingestão e processamento.

## Stack utilizada

- PostgreSQL
- Docker / Docker Compose
- Linux
- Bash
- Python para scripts e ETL
- Go para APIs e automação

## Como utilizar este repositório

Cada lab possui sua própria documentação e instruções de execução.

Exemplo:

```bash
cd labs/01-foundation
docker compose up -d
```

## Princípios do projeto

- Tudo deve ser **executável**
- Tudo deve ser **reproduzível**
- Tudo deve ser **testável**
- Falhas são **parte do aprendizado**
- Cada lab deve gerar evidências práticas do comportamento observado

## Estrutura do repositório

```text
postgresql-reliability-lab/
├── labs/
│   ├── 01-foundation/
│   ├── 02-database-initialization/
│   ├── 03-backup-restore/
│   ├── 04-replication/
│   └── 05-failover/
├── scripts/
├── datasets/
└── docs/
```

## Status do projeto

Este projeto está em construção contínua, com foco em evolução incremental e evidências práticas.

## Autor

Engenheiro de Software com sólida experiência em ERP Protheus (AdvPL), atuando na construção e operação de plataformas de dados com PostgreSQL. Focado em confiabilidade, automação e práticas de engenharia para ambientes de produção, com ênfase na estabilidade, observabilidade e eficiência operacional.

## Observação

Este não é um projeto acadêmico.
É um laboratório prático orientado a problemas reais de engenharia.
