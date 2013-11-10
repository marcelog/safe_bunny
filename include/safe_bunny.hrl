-ifndef(SAFE_BUNNY_HRL_).
-define(SAFE_BUNNY_HRL_, 1).

-define(SAFE_BUNNY_MQ_DELIVER_TASK, safe_bunny_deliver).
-define(CREATE_TABLE_SQL(T), lists:flatten([
  "CREATE TABLE IF NOT EXISTS `", T, "` (",
  "  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,"
  "  `data` text,"
  "  `created_date` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
  "  PRIMARY KEY (`id`)"
  ") ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;"
])).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Shortcuts.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-define(SB_CFG, safe_bunny_config).

-endif.
