%%% @doc Main supervisor.
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
-module(safe_bunny_sup).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

-behaviour(supervisor).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Required Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include("safe_bunny.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
-export([start_link/0]).

%%% supervisor callbacks.
-export([init/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Starts the main supervisor.
-spec start_link() -> supervisor:startlink_ret().
start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Supervisor API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Called by the supervisor behavior, returns children specs.
-spec init([]) ->
  {ok, {{supervisor:strategy(),pos_integer(),pos_integer()},[supervisor:child_spec()]}}
  | ignore.
init([]) ->
  CxyLimits = ?SB_CFG:concurrency_limits(),
  lager:debug("Initializing cxy limits: ~p", [CxyLimits]),
  cxy_ctl:init(CxyLimits),
  % Create ETS table (for ETS producer/consumer), so the sup owns it.
  Ets = ?SB_CFG:ets_name(),
  Ets = ets:new(Ets, [
    ordered_set, public, named_table,
    {write_concurrency, true}, {read_concurrency, true}
  ]),

  % Create worker pool definition.
  ProducersSup = {safe_bunny_producer_sup,
    {safe_bunny_producer_sup, start_link, []},
    permanent, infinity, supervisor, [safe_bunny_producer_sup]
  },
  ConsumersSup = {safe_bunny_consumer_sup,
    {safe_bunny_consumer_sup, start_link, []},
    permanent, infinity, supervisor, [safe_bunny_consumer_sup]
  },
  MqConfig = ?SB_CFG:mq(),
  WPoolDef = pool_def(MqConfig),
  {ok, {{one_for_one, 5, 10}, [WPoolDef, ProducersSup, ConsumersSup]}}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Returns child specifications for rabbitmq pools.
-spec pool_def(proplists:proplist()) -> supervisor:child_spec().
pool_def(MqConfig) ->
  Workers = proplists:get_value(workers, MqConfig),
  WorkerDef = [safe_bunny_worker, [
    {overrun_warning, infinity},
    {workers, Workers},
    {worker, {safe_bunny_worker, MqConfig}}
  ]],
  {mq,
    {wpool, start_pool, WorkerDef},
    permanent, brutal_kill, supervisor, [wpool]
  }.
