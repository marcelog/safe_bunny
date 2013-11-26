-module(consumer_SUITE).

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
  complete_coverage/1
]).

-spec all() -> [atom()].
all() -> [
  complete_coverage
].

-spec init_per_testcase(term(), term()) -> void.
init_per_testcase(_TestCase, _Config) ->
  application:load(safe_bunny),
  application:set_env(safe_bunny, consumers, []),
  application:set_env(safe_bunny, producers, []),
  ok = safe_bunny:start(),
  [].

-spec end_per_testcase(term(), term()) -> void.
end_per_testcase(_TestCase, _Config) ->
  application:stop(safe_bunny),
  [].

-spec complete_coverage([term()]) -> ok.
complete_coverage(_Config) ->
  {noreply, state, hibernate} = safe_bunny_consumer:handle_cast(msg, state),
  {noreply, state, hibernate} = safe_bunny_consumer:handle_info(info, state),
  {reply, invalid_request, state, hibernate} = safe_bunny_consumer:handle_call(unknown, from, state),
  ok = safe_bunny_consumer:terminate(reason, state),
  {ok, state} = safe_bunny_consumer:code_change(oldvsn, state, extra).
