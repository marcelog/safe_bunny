-module(worker_SUITE).

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
init_per_testcase(TestCase, Config) ->
  helper_utils:start_needed_deps(),
  application:load(safe_bunny),
  application:set_env(safe_bunny, consumers, []),
  application:set_env(safe_bunny, producers, []),
  helper_utils:start(TestCase, Config).

-spec end_per_testcase(term(), term()) -> void.
end_per_testcase(TestCase, Config) ->
  helper_utils:stop().

-spec can_deliver([term()]) -> ok.
can_deliver(_Config) ->
  {ok, Client1} = helper_mq:start(<<"test">>),
  helper_mq:notify_when(Client1, <<"worker 1">>, self()),
  helper_mq:deliver_unsafe(<<"test">>, <<"worker 1">>),
  ok = receive
    {message, <<"worker 1">>} -> ok
  after 1000 ->
    timeout
  end,
  helper_mq:stop(Client1),
  ok.

-spec complete_coverage([term()]) -> ok.
complete_coverage(_Config) ->
  {noreply, state} = safe_bunny_worker:handle_cast(msg, state),
  {noreply, state} = safe_bunny_worker:handle_info(info, state),
  {reply, invalid_request, state} = safe_bunny_worker:handle_call(unknown, from, state),
  ok = safe_bunny_worker:terminate(reason, state),
  {ok, state} = safe_bunny_worker:code_change(oldvsn, state, extra).
