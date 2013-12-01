{incl_app, safe_bunny, details}.
{export, "logs/cover.data"}.
{excl_mods, safe_bunny, [
  safe_bunny_producer,

  helper_mq,
  helper_utils,

  bunny_SUITE,
  consumer_SUITE,
  ets_SUITE,
  file_SUITE,
  mysql_SUITE,
  redis_SUITE,
  worker_SUITE
]}.
{incl_dirs_r, ["test"]}.
{src_dirs, safe_bunny, ["test"]}.
