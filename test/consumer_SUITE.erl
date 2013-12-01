-module(consumer_SUITE).

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
  can_handle_empty_queues/1,
  complete_coverage/1
]).

-spec all() -> [atom()].
all() -> [
  can_handle_empty_queues,
  complete_coverage
].

-spec init_per_testcase(term(), term()) -> void.
init_per_testcase(TestCase, _Config) ->
  application:load(safe_bunny),
  Backends = case TestCase of
    can_handle_empty_queues -> [mysql, redis, file, ets] ;
    _ -> []
  end,
  application:set_env(safe_bunny, consumers, Backends),
  application:set_env(safe_bunny, producers, Backends),
  helper_utils:start().

-spec end_per_testcase(term(), term()) -> void.
end_per_testcase(_TestCase, _Config) ->
  helper_utils:stop().

-spec can_handle_empty_queues([term()]) -> ok.
can_handle_empty_queues(_Config) ->
  timer:sleep(1000).

-spec complete_coverage([term()]) -> ok.
complete_coverage(_Config) ->
  {noreply, state, hibernate} = safe_bunny_consumer:handle_cast(msg, state),
  {noreply, state, hibernate} = safe_bunny_consumer:handle_info(info, state),
  {reply, invalid_request, state, hibernate} = safe_bunny_consumer:handle_call(unknown, from, state),
  ok = safe_bunny_consumer:terminate(reason, state),
  {ok, state} = safe_bunny_consumer:code_change(oldvsn, state, extra).
