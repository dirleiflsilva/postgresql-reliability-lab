# Lab 04: Streaming Replication

Este lab reaproveita o modelo de e-commerce, as roles, os schemas e a carga inicial dos Labs 02/03 em um ambiente independente com PostgreSQL 16. Um **primary** aceita escritas e envia WAL para uma **réplica hot standby**, que atende consultas somente leitura. A replicação é **assíncrona**: o commit no primary não espera a réplica.

## Objetivos

- Inicializar a réplica com `pg_basebackup` e `standby.signal`.
- Observar streaming, posição de replay e retenção de WAL por slot físico.
- Comprovar que alterações no primary aparecem na réplica.
- Confirmar que a réplica rejeita escrita, inclusive como superusuário.
- Parar a réplica, continuar escrevendo no primary e verificar a recuperação ao retornar.

## Arquitetura

```text
cliente ── escrita/leitura ──> primary :5437
                                  │
                                  └── WAL / slot lab04_replica ──> replica :5438
                                                                   somente leitura
```

Os serviços usam uma rede própria do Compose e volumes separados. As portas do host são publicadas somente em `127.0.0.1`. Os outros labs não precisam estar ligados e seus volumes não são utilizados. Failover e promoção ficam para o Lab 05; se o primary parar, este lab não promove a réplica automaticamente.

## Como executar

Pré-requisitos: Docker com Compose e Bash. Execute os comandos no diretório do lab:

```bash
cd labs/04-replication
cp .env.example .env
# Edite .env e substitua as três senhas de exemplo.
docker compose up -d --wait --wait-timeout 150
bash scripts/check.sh
bash scripts/status.sh
bash scripts/reconnect_demo.sh
```

Não sobrescreva um `.env` já configurado. As credenciais são aplicadas às roles na primeira criação do volume; editar `.env` não altera senhas de um cluster existente. Para senhas com caracteres especiais, use a sintaxe de aspas do Compose no `.env`.

O usuário de replicação é fixo: `replicator`. As roles de aplicação herdadas dos labs anteriores mantêm senhas didáticas; este ambiente é destinado ao uso local.

Saídas finais esperadas:

```text
ok: primary, réplica read-only, slot, streaming, dados e propagação validados.
ok: escrita com réplica parada e recuperação após reconexão validadas.
```

O healthcheck confirma disponibilidade e, na réplica, modo de recuperação. Use `check.sh` para validar efetivamente a replicação; um standby pode estar disponível para leitura mesmo sem conexão com o primary.

## O que os scripts verificam

| Script | Comportamento |
|--------|---------------|
| `check.sh` | Confirma os papéis, slot ativo, streaming assíncrono, WAL receiver, estrutura, integridade, ownership, privilégios e fingerprint dos dados; insere uma sentinela, espera replay e verifica rejeição de escrita com SQLSTATE `25006` |
| `status.sh` | Mostra containers, posições de WAL, diferença em bytes e WAL retido pelo slot |
| `reconnect_demo.sh` | Valida a base, para a réplica, escreve uma sentinela no primary, reinicia a réplica e confirma sua chegada; tenta religar a réplica também em caso de falha |
| `start-replica.sh` | Executado pelo container: cria o passfile e faz bootstrap somente quando ainda não há cluster no volume |

As verificações aguardam até 60 segundos pelo LSN de referência. Execute-as sem escritas concorrentes nos dados de e-commerce: a comparação de fingerprints ocorre em duas consultas separadas. As sentinelas ficam em `audit.replication_probe` e são removidas após sucesso; uma execução interrompida pode deixar uma linha de diagnóstico. O roteiro de reconexão causa uma breve indisponibilidade de leitura na réplica.

## Conexões e inspeção manual

```bash
docker compose exec primary psql -U postgres -d appdb
docker compose exec replica psql -U postgres -d appdb
```

Ajuste usuário e banco se tiver alterado os padrões no `.env`.

No primary:

```sql
SELECT pg_is_in_recovery(); -- false
SELECT application_name, state, sync_state, replay_lsn FROM pg_stat_replication;
SELECT slot_name, active, wal_status FROM pg_replication_slots;
```

Na réplica:

```sql
SELECT pg_is_in_recovery(); -- true
SHOW transaction_read_only; -- on
SELECT status, slot_name, latest_end_lsn FROM pg_stat_wal_receiver;
SELECT count(*) FROM app.orders;
```

## Decisões técnicas e limites

- `pg_basebackup -R` grava a configuração de conexão e cria `standby.signal`. O slot físico `lab04_replica` é criado na inicialização do primary e usado tanto no backup quanto no streaming, protegendo o intervalo entre as duas etapas.
- O bootstrap usa um diretório temporário no mesmo volume, publicado somente após o backup terminar. Reiniciar a réplica reutiliza os dados existentes. Um volume sem `standby.signal` é recusado para evitar iniciar um segundo primary.
- A autenticação da replicação usa SCRAM. A senha fica em um passfile com modo `0600`, recriado em `/tmp` dentro do container; não é gravada em `primary_conninfo`. As variáveis de ambiente continuam visíveis para quem administra o Docker.
- `max_slot_wal_keep_size=1GB` limita a retenção pelo slot no checkpoint; não é um limite rígido para o disco. Uma réplica parada por tempo suficiente pode perder WAL necessário e exigir novo bootstrap. Monitore `wal_status` e o espaço disponível.
- A diferença de LSN em bytes mede trabalho pendente de replay. Tempo desde a última transação reproduzida pode crescer em um banco ocioso sem indicar atraso real.
- Replicação assíncrona permite leituras temporariamente desatualizadas e perda de commits ainda não reproduzidos em um failover. Replicação não substitui backup: exclusões e alterações indevidas também chegam à réplica.

## Parar e reiniciar

```bash
docker compose stop
docker compose up -d --wait
bash scripts/check.sh
```

Para descartar **todos os dados do Lab 04**, inclusive primary e réplica, e começar novamente (por exemplo, após perda do WAL exigido pelo slot):

```bash
docker compose down -v
docker compose up -d --wait --wait-timeout 150
bash scripts/check.sh
```

O reset completo é uma conveniência deste lab. Em produção, uma réplica pode ser reconstruída separadamente sem descartar o primary.

## Validação

**Status:** concluído. **Data da última validação:** 12/09/2026, com validação manual confirmada pelo usuário.

Em 07/09/2026, foram executados neste workspace:

- `docker compose config --quiet`: configuração aceita.
- `docker compose up -d --wait --wait-timeout 150`: primary e réplica healthy, com volumes novos.
- `bash scripts/reconnect_demo.sh`: verificações completas antes e depois da interrupção passaram; a escrita feita com a réplica parada foi reproduzida após a retomada.
- `bash -n` em todos os scripts Bash do lab: sem erros de sintaxe.

O status no índice foi atualizado para **concluído** após a validação manual.

## Referências

- [Streaming replication e hot standby — PostgreSQL 16](https://www.postgresql.org/docs/16/warm-standby.html)
- [pg_basebackup — PostgreSQL 16](https://www.postgresql.org/docs/16/app-pgbasebackup.html)
- [Configuração de replicação e retenção de WAL — PostgreSQL 16](https://www.postgresql.org/docs/16/runtime-config-replication.html)
