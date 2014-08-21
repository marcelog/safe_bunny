{incl_app, safe_bunny, details}.
{export, "logs/cover.data"}.
{excl_mods, safe_bunny, [
  safe_bunny_producer,

  helper_mq,
  safe_bunny_helper_backend_tests,
  safe_bunny_helper_utils,

  safe_bunny_bunny_SUITE,
  safe_bunny_config_SUITE,
  safe_bunny_consumer_SUITE,
  safe_bunny_ets_SUITE,
  safe_bunny_file_SUITE,
  safe_bunny_mysql_SUITE,
  safe_bunny_redis_SUITE,
  safe_bunny_worker_SUITE
]}.
{incl_dirs_r, ["../../../test"]}.
{src_dirs, safe_bunny, ["../../../test"]}.
