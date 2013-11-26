%%% @doc Uses an emysql pool to handle multiple connections to mysql for
%%% queuing items in a concurrent fashion.
%%%
%%% Copyright 2012 Marcelo Gornstein &lt;marcelog@@gmail.com&gt;
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%% @end
%%% @copyright Marcelo Gornstein <marcelog@gmail.com>
%%% @author Marcelo Gornstein <marcelog@gmail.com>
%%%
-module(safe_bunny_producer_mysql).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

-behavior(safe_bunny_producer).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Required Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include("safe_bunny.hrl").
-include_lib("emysql/include/emysql.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% safe_bunny_producer behavior.
-export([init/1, queue/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init(safe_bunny_producer:options()) -> ok|term().
init(Options) ->
  crypto:start(),
  application:start(emysql),
  Get = fun(Key) -> proplists:get_value(Key, Options) end,
  User = Get(user),
  Pass = Get(pass),
  Host = Get(host),
  Port = Get(port),
  Db = Get(db),
  Table = Get(table),
  PoolSize = Get(producer_connections),
	ok = emysql:add_pool(?MODULE, PoolSize, User, Pass, Host, Port, Db, utf8),
  #ok_packet{} = emysql:execute(?MODULE, ?CREATE_TABLE_SQL(Table)),
  ok = emysql:prepare(new_item, lists:flatten([
    "INSERT INTO `", Table, "` (`uuid`, `exchange`, `key`, `payload`) VALUES(?,?,?,?)"
  ])),
  ok.

-spec queue(safe_bunny_message:queue_payload()) -> ok|term().
queue(Message) ->
  #ok_packet{} = emysql:execute(?MODULE, new_item, [
    safe_bunny_message:id(Message),
    safe_bunny_message:exchange(Message),
    safe_bunny_message:key(Message),
    base64:encode(safe_bunny_message:payload(Message))
  ]),
  ok.
