# Lab 03: Backup & Restore

Este lab evolui a base criada no Lab 02 (roles, schemas, extensões, modelo de dados de e-commerce e carga inicial) adicionando estratégias de proteção de dados: backup lógico, backup físico, WAL archiving e recuperação point-in-time (PITR).

## Objetivo

Ao finalizar este lab, o ambiente deve permitir:

- gerar e restaurar um backup lógico (`pg_dump` / `pg_restore`)
- gerar e restaurar um backup físico (`pg_basebackup`)
- manter WAL archiving ativo (`archive_mode=on`)
- simular um incidente (perda de dados) e recuperar o banco para um instante
  anterior ao incidente (PITR), usando o backup físico de base + os WALs arquivados

## Estrutura

```text
labs/03-backup-restore/
├── .env.example
├── docker-compose.yml
├── init/                     # roles, extensões, schemas, tabelas e carga (mesmo do Lab 02)
├── scripts/
│   ├── _common.sh            # helper compartilhado (não executar diretamente)
│   ├── check.sh               # valida o estado base do ambiente
│   ├── backup_logical.sh       # pg_dump -Fc
│   ├── restore_logical.sh      # pg_restore em banco separado + comparação de linhas
│   ├── backup_physical.sh      # pg_basebackup via backup_user
│   ├── restore_physical.sh     # sobe um container temporário a partir do backup físico
│   └── pitr_demo.sh            # roteiro completo de incidente + PITR
├── backups/
│   ├── logical/                 # dumps gerados por backup_logical.sh (ignorado no git)
│   └── physical/                # base backups gerados por backup_physical.sh (ignorado no git)
├── wal_archive/                 # WALs arquivados pelo archive_command (ignorado no git)
└── README.md
```

## Scripts de inicialização

Os scripts em `init/` são os mesmos do Lab 02 (roles, extensões, schemas, tabelas, procedure de seed e carga de dados) e rodam automaticamente na primeira inicialização do volume. Consulte o [README do Lab 02](../02-database-initialization/README.md) para o detalhamento de cada arquivo.

## Como subir o ambiente

1. Entre no diretório do lab:

```bash
cd labs/03-backup-restore
```

2. Crie o arquivo `.env`:

```bash
cp .env.example .env
```

3. Ajuste `POSTGRES_PASSWORD` e `BACKUP_USER_PASSWORD` no `.env` antes de subir o ambiente (devem coincidir com as senhas definidas em `init/01_roles.sql`, que são apenas para uso local do lab).

4. Crie os diretórios de backup/WAL archive com permissão de escrita para qualquer usuário. Isso é necessário porque o PostgreSQL dentro do container roda como o usuário `postgres` (uid 999), diferente do usuário do host que cria os diretórios via bind mount:

```bash
mkdir -p wal_archive backups/logical backups/physical
chmod 777 wal_archive backups/logical backups/physical
```

5. Inicie o PostgreSQL:

```bash
docker compose up -d
```

6. Verifique o estado do container:

```bash
docker compose ps
```

O serviço deve ficar com status `healthy` após a inicialização.

## Como validar o estado base

```bash
chmod +x scripts/*.sh
./scripts/check.sh
```

O resultado esperado é:

```text
ok: backup & restore validado (roles, schemas, extensões, dados e WAL archiving).
```

Esse script valida apenas o estado base do ambiente (roles, schemas, extensões, dados e configuração de WAL). Os cenários de backup, restore e PITR são exercitados manualmente pelos scripts abaixo.

## Backup e restore lógico

```bash
./scripts/backup_logical.sh
./scripts/restore_logical.sh
```

- `backup_logical.sh` gera `backups/logical/appdb_<timestamp>.dump` com `pg_dump -Fc`.
- `restore_logical.sh` restaura o dump mais recente (ou um arquivo específico passado como argumento) em um banco `appdb_restore`, e compara a contagem de linhas de cada tabela contra o banco de origem.

## Backup e restore físico

```bash
./scripts/backup_physical.sh
./scripts/restore_physical.sh
```

- `backup_physical.sh` usa `pg_basebackup` autenticado como `backup_user` (role criada em `init/01_roles.sql` com o atributo `REPLICATION`) e grava o resultado em `backups/physical/<timestamp>/`.
- `restore_physical.sh` copia o backup físico mais recente (ou um timestamp específico passado como argumento) para uma área isolada, sobe um container Postgres temporário a partir dela na porta `VERIFY_PHYSICAL_PORT` (padrão `5435`) e valida que os dados batem com o esperado. O container temporário é removido automaticamente ao final.

## WAL archiving e PITR

O `docker-compose.yml` inicia o PostgreSQL com:

- `wal_level=replica`
- `archive_mode=on`
- `archive_command=cp %p /var/lib/postgresql/wal_archive/%f` (idempotente, não sobrescreve um arquivo já arquivado)

Os WALs arquivados ficam disponíveis no host em `wal_archive/`, montado como volume no container.

### Roteiro guiado de incidente + PITR

```bash
./scripts/pitr_demo.sh
```

Esse script automatiza o cenário completo:

1. Confirma que `archive_mode` está ativo.
2. Gera um backup físico de base (`pg_basebackup`).
3. Registra um timestamp de referência e aguarda alguns segundos.
4. **Simula um incidente**: apaga os dados de `app.payments`, `app.order_items` e `app.orders` no ambiente principal do lab, e força um `pg_switch_wal()` para garantir que o WAL do incidente seja arquivado.
5. Copia o backup de base para uma área isolada, configura `recovery_target_time` com o timestamp do passo 3 e `restore_command` apontando para `wal_archive/`.
6. Sobe um container temporário na porta `VERIFY_PITR_PORT` (padrão `5436`), aguarda o replay de WAL e a promoção do cluster restaurado.
7. Compara a contagem de `app.orders` antes do incidente, depois do incidente (no ambiente principal, que permanece com os dados apagados) e no cluster restaurado via PITR.

> **Atenção:** este script apaga dados reais do ambiente principal do lab para simular o incidente — isso
> é intencional, faz parte da demonstração.
> Para repor o ambiente principal ao estado inicial (com carga completa), recrie o volume:
>
> ```bash
> docker compose down -v
> docker compose up -d
> ```

## Como conectar via psql

```bash
docker compose exec postgres psql -U postgres -d appdb
```

```bash
psql "postgresql://postgres:SUA_SENHA@localhost:5434/appdb"
```

## Decisões técnicas

- Scripts separados por estratégia (`backup_logical`, `backup_physical`, `pitr_demo`): cada cenário fica isolado e pode ser executado independentemente, sem misturar propósitos.
- `backup_user` reaproveitado do Lab 02: reforça a continuidade entre labs — a role já nasceu preparada (`LOGIN REPLICATION`) para este cenário.
- Restore físico e PITR sobem containers `postgres:16` temporários via `docker run`, isolados do serviço principal do `docker-compose.yml`: valida o backup de forma realista (cluster independente) sem arriscar o ambiente principal do lab.
- Cópia da área de backup (`cp -a`) antes de qualquer restore: preserva o backup original intacto, permitindo repetir a validação quantas vezes for necessário.
- `archive_command` idempotente (`test ! -f ... && cp`): evita erro do PostgreSQL ao tentar arquivar um WAL cujo destino já existe (cenário comum após reinícios).
- Porta `5434`: evita conflito com os Labs 01 (`5432`) e 02 (`5433`).

## Observações

- `backups/` e `wal_archive/` são ignorados pelo Git (dados binários, gerados localmente).
- Os diretórios `backups/physical/<timestamp>-verify/` e `backups/physical/<timestamp>-pitr/` são cópias de trabalho criadas pelos scripts de restore/PITR; podem ser removidos livremente.
- As senhas definidas nos scripts de `init/` são apenas para uso local do lab. Em um ambiente real, backup e restore devem usar segredos gerenciados e, idealmente, ferramentas dedicadas como `pgBackRest` ou `Barman` — fora do escopo deste lab, que foca nos mecanismos nativos do PostgreSQL.

## Referências

- `pg_dump` / `pg_restore`: https://www.postgresql.org/docs/current/app-pgdump.html
- `pg_basebackup`: https://www.postgresql.org/docs/current/app-pgbasebackup.html
- Continuous Archiving and Point-in-Time Recovery (PITR): https://www.postgresql.org/docs/current/continuous-archiving.html
- Configuração de recuperação (`recovery_target_time`, `restore_command`): https://www.postgresql.org/docs/current/runtime-config-wal.html#RUNTIME-CONFIG-WAL-ARCHIVE-RECOVERY
