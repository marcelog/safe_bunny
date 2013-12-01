-module(ets_SUITE).

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
  can_deliver/1,
  complete_coverage/1
]).

-spec all() -> [atom()].
all() -> [
  can_deliver,
  complete_coverage
].

-spec init_per_testcase(term(), term()) -> void.
init_per_testcase(_TestCase, _Config) ->
  application:load(safe_bunny),
  application:set_env(safe_bunny, consumers, [ets]),
  application:set_env(safe_bunny, producers, [ets]),
  {ok, MysqlConfig} = application:get_env(safe_bunny, ets),
  application:set_env(
    safe_bunny, ets,
    lists:keystore(consumer_poll, 1, MysqlConfig, {consumer_poll, 500})
  ),
  helper_utils:start().

-spec end_per_testcase(term(), term()) -> void.
end_per_testcase(_TestCase, _Config) ->
  helper_utils:stop().

-spec can_deliver([term()]) -> ok.
can_deliver(_Config) ->
  {ok, Client1} = helper_mq:start(<<"test">>),
  helper_mq:notify_when(Client1, <<"1">>, self()),
  helper_mq:queue(<<"test">>, <<"1">>),
  ok = receive
    {message, <<"1">>} -> ok
  after 1000 ->
    timeout
  end,
  helper_mq:stop(Client1),
  ok.

-spec complete_coverage([term()]) -> ok.
complete_coverage(_Config) ->
  {noreply, state} = safe_bunny_producer_ets:handle_cast(msg, state),
  {noreply, state} = safe_bunny_producer_ets:handle_info(info, state),
  {reply, {invalid_request, unknown}, state} = safe_bunny_producer_ets:handle_call(unknown, from, state),
  {ok, state} = safe_bunny_producer_ets:code_change(oldvsn, state, extra),
  ok = safe_bunny_producer_ets:terminate(reason, state),
  ok = safe_bunny_consumer_ets:terminate(reason, state).