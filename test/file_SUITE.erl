-module(file_SUITE).

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
  application:set_env(safe_bunny, consumers, [file]),
  application:set_env(safe_bunny, producers, [file]),
  {ok, MysqlConfig} = application:get_env(safe_bunny, file),
  application:set_env(
    safe_bunny, file,
    lists:keystore(consumer_poll, 1, MysqlConfig, {consumer_poll, 500})
  ),
  ok = safe_bunny:start(),
	[].

-spec end_per_testcase(term(), term()) -> void.
end_per_testcase(_TestCase, _Config) ->
  application:stop(safe_bunny),
  [].

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
  ok = safe_bunny_consumer_file:terminate(reason, state).