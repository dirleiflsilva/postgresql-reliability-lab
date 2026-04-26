# PostgreSQL Reliability Lab

Laboratórios práticos de engenharia do PostgreSQL, orientados à produção, com foco em confiabilidade, alta disponibilidade e desempenho.

## Objetivos

- Construir cenários reais com PostgreSQL
- Simular falhas e recuperação
- Implementar alta disponibilidade, backup e observabilidade
- Fornecer ambientes reproduzíveis usando Docker

## Laboratórios

- [x] 01 - Fundamentos (nó único)
- [ ] 02 - Backup e Restauração
- [ ] 03 - Replicação
- [ ] 04 - Failover
- [ ] 05 - Observabilidade
- [ ] 06 - Desempenho
- [ ] 07 - Pipeline de Dados

# PostgreSQL Reliability Lab

Laboratório prático de engenharia de banco de dados com foco em confiabilidade, alta disponibilidade e operação em ambientes de produção utilizando PostgreSQL.

---

## Objetivo

Este projeto tem como objetivo desenvolver, de forma prática e orientada à produção, as competências necessárias para atuar como **PostgreSQL Database Engineer / Data Platform Engineer**.

O foco não está apenas em aprender PostgreSQL, mas em **operar, escalar e garantir a confiabilidade de bancos de dados em cenários reais**, incluindo falhas controladas.

---

## Abordagem

O projeto é estruturado como um conjunto de **labs executáveis**, onde cada cenário simula um problema real de engenharia:

- Ambientes reproduzíveis com Docker
- Simulação de falhas
- Recuperação de desastres
- Validação com evidências (logs, métricas, testes)

---

## Estrutura dos Labs

Cada lab é independente, mas segue uma evolução natural de complexidade:

| Status | Lab | Descrição |
|--------|-----|----------|
| ✅ | 01 - Foundation | Ambiente PostgreSQL single-node com boas práticas |
| ⏳ | 02 - Backup & Restore | Estratégias de backup lógico e físico + recuperação |
| ⏳ | 03 - Replication | Replicação streaming (primary + replica) |
| ⏳ | 04 - Failover | Cluster com failover automático |
| ⏳ | 05 - Observability | Monitoramento com métricas e dashboards |
| ⏳ | 06 - Performance | Análise e otimização de queries |
| ⏳ | 07 - Data Pipeline | Ingestão e processamento de dados |

**Legenda:**
- 🚧 Em desenvolvimento  
- ⏳ Planejado  
- ✅ Concluído  

---

## Stack utilizada

- PostgreSQL  
- Docker / Docker Compose  
- Linux  
- Python (scripts / ETL)  
- Go (APIs e automação)  

---

## Como utilizar este repositório

Cada lab possui sua própria documentação e instruções de execução.

Exemplo:

```bash
cd labs/01-foundation
docker compose up -d
```

---

## Princípios do projeto

- Tudo deve ser **executável**
- Tudo deve ser **reproduzível**
- Tudo deve ser **testável**
- Falhas são **parte do aprendizado**

---

## Estrutura do repositório

```text
postgresql-reliability-lab/
├── labs/
├── scripts/
├── datasets/
├── docs/
```

---

## Status do projeto

Este projeto está em construção contínua, com foco em evolução incremental e evidências práticas.

---

## Autor

Desenvolvedor com sólida experiência em ERP Protheus (AdvPL), especializado em PostgreSQL, com foco em confiabilidade, automação e engenharia de plataformas de dados em ambientes de produção.

---

## Observação

Este não é um projeto acadêmico.
É um laboratório prático orientado a problemas reais de engenharia.
