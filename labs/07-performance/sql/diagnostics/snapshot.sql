SELECT json_build_object(
 'time', clock_timestamp(), 'node', inet_server_addr(), 'version', version(),
 'wal', pg_current_wal_lsn(), 'database_bytes', pg_database_size(current_database()),
 'settings', (SELECT json_object_agg(name,setting) FROM pg_settings WHERE name IN
 ('shared_buffers','work_mem','effective_cache_size','random_page_cost','track_io_timing','shared_preload_libraries')),
 'reset', (SELECT row_to_json(i) FROM pg_stat_statements_info i),
 'statements', (SELECT coalesce(json_agg(s),'[]') FROM (SELECT userid,dbid,queryid,calls,total_exec_time,shared_blks_hit,shared_blks_read,query FROM pg_stat_statements WHERE dbid=(SELECT oid FROM pg_database WHERE datname=current_database())) s),
 'replication', (SELECT json_agg(r) FROM (SELECT application_name,state,replay_lsn FROM pg_stat_replication) r)
);
