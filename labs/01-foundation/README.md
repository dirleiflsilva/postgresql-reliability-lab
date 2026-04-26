# Lab 01: Foundation

Este lab cria um ambiente PostgreSQL single-node com Docker Compose, persistência em volume nomeado, healthcheck e inicialização automática do schema no primeiro boot.

## Objetivo

Subir um PostgreSQL 16 com configuração base próxima de produção para servir como fundamento dos próximos labs do projeto.

Ao finalizar este lab, o ambiente deve:

- iniciar com `docker compose up -d`
- criar automaticamente o banco `app`
- aplicar o script SQL inicial
- responder a validações de conectividade e consulta

## Estrutura

```text
labs/01-foundation/
├── .env.example
├── docker-compose.yml
├── init/
│   └── init.sql
├── scripts/
│   └── check.sh
└── README.md
```

## Como subir o ambiente

1. Entre no diretório do lab:

```bash
cd labs/01-foundation
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

## Como conectar via psql

Use sempre os valores definidos no arquivo `.env`, principalmente a senha configurada em `POSTGRES_PASSWORD`.

Via cliente `psql` no host:

```bash
psql "postgresql://SEU_USUARIO:SUA_SENHA@localhost:SUA_PORTA/SEU_BANCO"
```

Via container:

```bash
docker compose exec postgres psql -U "SEU_USUARIO" -d "SEU_BANCO"
```

Exemplo com os valores padrão do `.env.example`:

```bash
psql "postgresql://app_user:app1010@localhost:5432/app"
docker compose exec postgres psql -U "app_user" -d "app"
```

Esta e a forma recomendada para a validação do lab, porque deixa explícito quais valores estão sendo usados.

Também é possível usar variáveis no terminal, desde que elas estejam exportadas no shell do host:

```bash
export POSTGRES_USER=app_user
export POSTGRES_PASSWORD=app1010
export POSTGRES_PORT=5432
export POSTGRES_DB=app

psql "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT}/${POSTGRES_DB}"
docker compose exec postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"
```

Sem esse `export`, `${POSTGRES_USER}` e `${POSTGRES_DB}` serão expandidas pelo shell do host antes do comando rodar e podem ficar vazias, mesmo que o `.env` exista no diretório do lab.

## Como validar o funcionamento

Execute o script de verificação:

```bash
chmod +x scripts/check.sh
./scripts/check.sh
```

O resultado esperado é:

```text
ok: PostgreSQL operacional e tabela users acessível.
```

Também é possível validar manualmente:

```bash
docker compose exec postgres psql -U "SEU_USUARIO" -d "SEU_BANCO" -c "TABLE users;"
```

## Inicialização do banco

O arquivo `init/init.sql` é executado automaticamente no primeiro bootstrap do volume de dados. Ele:

- usa o banco definido por `POSTGRES_DB`
- cria a tabela `users`
- insere registros iniciais de exemplo

O valor padrão em `.env.example` define `POSTGRES_DB=app`, então o banco `app` já nasce como banco principal do lab.

## Decisões Técnicas

- Volume nomeado: preserva os dados entre reinícios e recriações do container.
- Healthcheck com `pg_isready`: expõe prontidão real do PostgreSQL para validação operacional.
- Script SQL em `/docker-entrypoint-initdb.d`: automatiza schema e seed inicial sem passos manuais.
- Variáveis em `.env`: evita credenciais hardcoded no `docker-compose.yml` e facilita customizacao local.

## Observações

- Os scripts de inicialização rodam apenas quando o volume está vazio.
- Se você alterar `init.sql` depois da primeira subida, recrie o volume para reaplicar a inicialização:

```bash
docker compose down -v
docker compose up -d
```

## Referências

- `pg_isready`: utilitário oficial do PostgreSQL para verificar se o servidor está aceitando conexões. Documentação: https://www.postgresql.org/docs/current/app-pg-isready.html
- `/docker-entrypoint-initdb.d`: diretório suportado pela imagem oficial `postgres` para executar scripts de inicialização no primeiro bootstrap do volume. Documentação: https://hub.docker.com/_/postgres
- Guia adicional da Docker sobre inicialização automática com scripts: https://docs.docker.com/guides/postgresql/advanced-configuration-and-initialization/
