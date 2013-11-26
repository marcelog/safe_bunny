{incl_app, safe_bunny, details}.
{export, "logs/cover.data"}.
{excl_mods, safe_bunny, [
  helper_mq,
  
  ets_SUITE,
  file_SUITE,
  mysql_SUITE,
  redis_SUITE
]}.
{incl_dirs_r, ["test"]}.
{src_dirs, safe_bunny, ["test"]}.
