-module(helper_backend_tests).

-export([all/0, init_per_testcase/3, end_per_testcase/3]).
-export([
  can_deliver/2,
  can_deliver_eventually/2,
  can_drop_safe_on_max_attempts/2,
  can_drop_unsafe_on_max_attempts/2,
  complete_coverage/2
]).

-spec all() -> [atom()].
all() -> [
  can_deliver,
  can_deliver_eventually,
  can_drop_safe_on_max_attempts,
  can_drop_unsafe_on_max_attempts,
  complete_coverage
].

-spec init_per_testcase(atom(), term(), term()) -> void.
init_per_testcase(Backend, TestCase, Config) ->
  helper_utils:start_needed_deps(),
  application:load(safe_bunny),
  application:set_env(safe_bunny, consumers, [Backend]),
  application:set_env(safe_bunny, producers, [Backend]),
  if
    TestCase =:= can_drop_safe_on_max_attempts
    orelse can_drop_unsafe_on_max_attempts ->
      {ok, Options} = application:get_env(safe_bunny, Backend),
      application:set_env(
        safe_bunny, Backend, lists:keystore(maximum_retries, 1, Options, {maximum_retries, 1})
      ),
      {ok, MqOptions} = application:get_env(safe_bunny, mq),
      application:set_env(
        safe_bunny, mq, lists:keystore(reconnect_timeout, 5, MqOptions, {reconnect_timeout, 5})
      );
    true -> ok
  end,
  helper_utils:start(TestCase, Config).

-spec end_per_testcase(atom(), term(), term()) -> void.
end_per_testcase(_Backend, _TestCase, _Config) ->
  helper_utils:stop().

-spec can_deliver(atom(), [term()]) -> ok.
can_deliver(Backend, _Config) ->
  BackendBin = list_to_binary(atom_to_list(Backend)),
  TestText = <<BackendBin/binary, " 1">>,
  {ok, Client1} = helper_mq:start(<<"test">>),
  helper_mq:notify_when(Client1, TestText, self()),
  helper_mq:queue(<<"test">>, TestText),
  ok = receive
    {message, TestText} -> ok
  after 1000 ->
    timeout
  end,
  helper_mq:stop(Client1),
  ok.

-spec can_deliver_eventually(atom(), [term()]) -> ok.
can_deliver_eventually(Backend, _Config) ->
  BackendBin = list_to_binary(atom_to_list(Backend)),
  TestText = <<BackendBin/binary, " 2">>,
  {ok, Client1} = helper_mq:start(<<"test">>),
  helper_mq:deliver_safe(<<"test2">>, TestText),
  helper_mq:deliver_safe(<<"test2">>, TestText),
  helper_mq:deliver_safe(<<"test2">>, TestText),
  timer:sleep(100),
  helper_mq:stop(Client1),
  {ok, Client2} = helper_mq:start_listening(<<"test2">>, [{TestText, self()}]),
  lists:foreach(fun(_) ->
    ok = receive
      {message, TestText} -> ok
    after 2000 ->
      timeout
    end
  end, lists:seq(1, 3)),
  helper_mq:stop(Client2),
  ok.

-spec can_drop_safe_on_max_attempts(atom(), [term()]) -> ok.
can_drop_safe_on_max_attempts(Backend, Config) ->
  can_drop_on_max_attempts(Backend, true, Config).

-spec can_drop_unsafe_on_max_attempts(atom(), [term()]) -> ok.
can_drop_unsafe_on_max_attempts(Backend, Config) ->
  can_drop_on_max_attempts(Backend, false, Config).

-spec complete_coverage(atom(), [term()]) -> ok.
complete_coverage(Backend, _Config) ->
  ConsumerModule = safe_bunny:consumer_module(Backend),
  ProducerModule = safe_bunny:producer_module(Backend),
  {noreply, state} = ProducerModule:handle_cast(msg, state),
  {noreply, state} = ProducerModule:handle_info(info, state),
  {reply, {invalid_request, unknown}, state} = ProducerModule:handle_call(unknown, from, state),
  {ok, state} = ProducerModule:code_change(oldvsn, state, extra),
  ok = ConsumerModule:terminate(reason, state),
  ok = ProducerModule:terminate(reason, state).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
can_drop_on_max_attempts(Backend, Safe, _Config) ->
  BackendBin = list_to_binary(atom_to_list(Backend)),
  TestText = <<BackendBin/binary, " 3">>,
  timer:sleep(2000),
  Fun = case Safe of
    false -> deliver_unsafe;
    true -> deliver_safe
  end,
  helper_mq:Fun(<<"test3">>, TestText),
  timer:sleep(2000),
  {ok, Client1} = helper_mq:start_listening(<<"test3">>, [{TestText, self()}]),
  ok = receive
    {message, TestText} -> should_have_expired
  after 1000 ->
    ok
  end,
  helper_mq:stop(Client1),
  ok.
