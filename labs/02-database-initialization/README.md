# Lab 02: Database Initialization

Este lab cria uma base PostgreSQL minimamente realista para sustentar os próximos cenários de backup, replicação, failover, observabilidade, performance e pipeline de dados.

## Objetivo

Evoluir a fundação criada no Lab 01 para uma estrutura de banco mais próxima de um ambiente real.

Ao finalizar este lab, o ambiente deve:

- iniciar com `docker compose up -d`
- criar roles operacionais e de aplicação
- criar schemas separados por responsabilidade
- habilitar extensões úteis para operação e diagnóstico
- criar um modelo de dados simples de e-commerce
- carregar uma massa inicial pequena e reproduzível
- responder a validações automatizadas

## Estrutura

```text
labs/02-database-initialization/
├── .env.example
├── docker-compose.yml
├── init/
│   ├── 01_roles.sql
│   ├── 02_extensions.sql
│   ├── 03_schemas.sql
│   ├── 04_tables.sql
│   ├── 05_seed_procedures.sql
│   └── 06_load_sample_data.sql
├── scripts/
│   └── check.sh
└── README.md
```

## Scripts de inicialização

O PostgreSQL executa os arquivos do diretório `init/` em ordem alfabética na
primeira inicialização do volume:

- `01_roles.sql`: cria as roles de propriedade, aplicação, leitura, backup e
  monitoramento; também configura a associação de `app_user` com `app_owner` e
  concede `pg_monitor` a `monitor_user`.
- `02_extensions.sql`: habilita as extensões `pg_stat_statements`, `pgcrypto` e
  `uuid-ossp`.
- `03_schemas.sql`: cria os schemas `app`, `audit` e `seed`, restringe o schema
  `public` e configura permissões e privilégios padrão para as roles do lab.
- `04_tables.sql`: cria as tabelas do e-commerce e de auditoria, com chaves,
  restrições e índices, usando `app_owner` como proprietária dos objetos.
- `05_seed_procedures.sql`: cria a procedure `seed.load_sample_data`, responsável
  por gerar clientes, categorias, produtos, pedidos, pagamentos e eventos de
  auditoria, e concede sua execução a `app_user`.
- `06_load_sample_data.sql`: executa a procedure de carga com os valores padrão
  do lab para popular o banco durante a inicialização.

Esses scripts só são executados automaticamente quando o diretório de dados do
PostgreSQL está vazio. Para executá-los novamente, é necessário recriar o volume,
conforme mostrado na seção "Dados iniciais".

## Como subir o ambiente

1. Entre no diretório do lab:

```bash
cd labs/02-database-initialization
```

2. Crie o arquivo `.env`:

```bash
cp .env.example .env
```

3. Ajuste `POSTGRES_PASSWORD` no `.env` antes de subir o ambiente.

4. Inicie o PostgreSQL:

```bash
docker compose up -d
```

5. Verifique o estado do container:

```bash
docker compose ps
```

O serviço deve ficar com status `healthy` após a inicialização.

## Como validar o funcionamento

Execute o script de verificação:

```bash
chmod +x scripts/check.sh
./scripts/check.sh
```

O resultado esperado é:

```text
ok: database initialization validado com roles, schemas, extensões, tabelas e dados.
```

## Como conectar via psql

Via container:

```bash
docker compose exec postgres psql -U postgres -d appdb
```

Via cliente `psql` no host:

```bash
psql "postgresql://postgres:SUA_SENHA@localhost:5433/appdb"
```

## Modelo de dados

O lab usa um domínio simples de e-commerce:

- `app.customers`
- `app.addresses`
- `app.categories`
- `app.products`
- `app.orders`
- `app.order_items`
- `app.payments`
- `audit.events`

Esse modelo permite exercitar joins, chaves estrangeiras, índices, agregações, backups, restores, replicação e consultas para análise de performance.

## Roles

O script de inicialização cria as seguintes roles:

- `app_owner`: dona dos objetos de aplicação
- `app_user`: role de leitura e escrita usada pela aplicação
- `readonly`: role de consulta
- `backup_user`: role preparada para cenários de backup físico e replicação
- `monitor_user`: role com privilégios de monitoramento via `pg_monitor`

As senhas definidas nos scripts são apenas para laboratório local. Em um ambiente real, elas devem ser gerenciadas por um mecanismo seguro de secrets.

## Extensões

O lab habilita:

- `pg_stat_statements`
- `pgcrypto`
- `uuid-ossp`

O `docker-compose.yml` também inicializa o PostgreSQL com `shared_preload_libraries=pg_stat_statements` e `track_io_timing=on`, preparando o ambiente para os labs de observabilidade e performance.

## Validação manual no psql

Depois de conectar ao banco `appdb`, use os metacomandos abaixo no prompt do
`psql` para inspecionar os objetos criados pelo lab:

```psql
\conninfo
\dn
\dt app.*
\dt audit.*
\du
\dx
```

O resultado deve mostrar:

- os schemas `app`, `audit` e `seed` no comando `\dn`
- sete tabelas no schema `app` e a tabela `audit.events` nos comandos `\dt`
- as roles `app_owner`, `app_user`, `readonly`, `backup_user` e `monitor_user`
  no comando `\du`
- as extensões `pg_stat_statements`, `pgcrypto` e `uuid-ossp` no comando `\dx`

Para examinar a estrutura de uma tabela específica, incluindo colunas, índices
e chaves estrangeiras, use `\d` com o nome qualificado da tabela. Por exemplo:

```psql
\d app.orders
\d app.order_items
```

### Consultas de exemplo

As consultas abaixo permitem conferir rapidamente os dados carregados nas
tabelas do lab:

```sql
SELECT * FROM app.categories ORDER BY category_id;

SELECT * FROM app.customers ORDER BY customer_id LIMIT 10;

SELECT * FROM app.addresses ORDER BY address_id LIMIT 10;

SELECT * FROM app.products ORDER BY product_id LIMIT 10;

SELECT * FROM app.orders ORDER BY order_id LIMIT 10;

SELECT * FROM app.order_items ORDER BY order_item_id LIMIT 10;

SELECT * FROM app.payments ORDER BY payment_id LIMIT 10;

SELECT * FROM audit.events ORDER BY event_id LIMIT 10;
```

Para obter um resumo da quantidade de registros em cada tabela:

```sql
SELECT 'app.customers' AS table_name, count(*) AS row_count FROM app.customers
UNION ALL
SELECT 'app.addresses', count(*) FROM app.addresses
UNION ALL
SELECT 'app.categories', count(*) FROM app.categories
UNION ALL
SELECT 'app.products', count(*) FROM app.products
UNION ALL
SELECT 'app.orders', count(*) FROM app.orders
UNION ALL
SELECT 'app.order_items', count(*) FROM app.order_items
UNION ALL
SELECT 'app.payments', count(*) FROM app.payments
UNION ALL
SELECT 'audit.events', count(*) FROM audit.events
ORDER BY table_name;
```

Para sair do `psql`, execute:

```psql
\q
```

## Dados iniciais

A procedure `seed.load_sample_data` carrega, por padrão:

- 100 clientes
- 5 categorias
- 50 produtos
- 500 pedidos
- itens de pedido, pagamentos e eventos de auditoria relacionados

Para recarregar o ambiente do zero, remova o volume e suba novamente:

```bash
docker compose down -v
docker compose up -d
```

## Decisões técnicas

- Scripts SQL numerados: deixam a ordem de bootstrap explícita.
- Schemas separados: isolam aplicação, auditoria e geração de dados.
- Roles dedicadas: aproximam o lab de uma topologia operacional real.
- Dados via PL/pgSQL: tornam a carga reproduzível sem depender de arquivos externos.
- Porta `5433`: evita conflito com o Lab 01, que usa `5432` por padrão.
