-module(safe_bunny_helper_backend_tests).

-export([all/0, init_per_testcase/3, end_per_testcase/3]).
-export([
  can_deliver/2,
  can_deliver_eventually/2,
  can_drop_safe_on_max_attempts/2,
  can_drop_unsafe_on_max_attempts/2,
  can_deliver_with_mq_down/2,
  can_cycle_through_poll_timers/2,
  complete_coverage/2
]).

-spec all() -> [atom()].
all() -> [
  can_deliver,
  can_deliver_eventually,
  can_drop_safe_on_max_attempts,
  can_drop_unsafe_on_max_attempts,
  can_deliver_with_mq_down,
  can_cycle_through_poll_timers,
  complete_coverage
].

-spec init_per_testcase(atom(), term(), term()) -> void.
init_per_testcase(Backend, TestCase, Config) ->
  safe_bunny_helper_utils:start_needed_deps(),
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
  safe_bunny_helper_utils:start(TestCase, Config).

-spec end_per_testcase(atom(), term(), term()) -> void.
end_per_testcase(_Backend, _TestCase, _Config) ->
  safe_bunny_helper_utils:stop().

-spec can_deliver(atom(), [term()]) -> ok.
can_deliver(Backend, _Config) ->
  BackendBin = list_to_binary(atom_to_list(Backend)),
  TestText = <<BackendBin/binary, " 1">>,
  {ok, Client1} = safe_bunny_helper_mq:start(<<"test">>),
  safe_bunny_helper_mq:notify_when(Client1, TestText, self()),
  safe_bunny_helper_mq:queue(<<"test">>, TestText),
  ok = receive
    {message, TestText} -> ok
  after 5000 ->
    timeout
  end,
  safe_bunny_helper_mq:stop(Client1),
  ok.

-spec can_deliver_eventually(atom(), [term()]) -> ok.
can_deliver_eventually(Backend, _Config) ->
  BackendBin = list_to_binary(atom_to_list(Backend)),
  TestText = <<BackendBin/binary, " 2">>,
  {ok, Client1} = safe_bunny_helper_mq:start(<<"test">>),
  safe_bunny_helper_mq:deliver_safe(<<"test2">>, TestText),
  safe_bunny_helper_mq:deliver_safe(<<"test2">>, TestText),
  safe_bunny_helper_mq:deliver_safe(<<"test2">>, TestText),
  timer:sleep(100),
  safe_bunny_helper_mq:stop(Client1),
  {ok, Client2} = safe_bunny_helper_mq:start_listening(<<"test2">>, [{TestText, self()}]),
  lists:foreach(fun(_) ->
    ok = receive
      {message, TestText} -> ok
    after 2000 ->
      timeout
    end
  end, lists:seq(1, 3)),
  safe_bunny_helper_mq:stop(Client2),
  ok.

-spec can_drop_safe_on_max_attempts(atom(), [term()]) -> ok.
can_drop_safe_on_max_attempts(Backend, Config) ->
  can_drop_on_max_attempts(Backend, true, Config).

-spec can_drop_unsafe_on_max_attempts(atom(), [term()]) -> ok.
can_drop_unsafe_on_max_attempts(Backend, Config) ->
  can_drop_on_max_attempts(Backend, false, Config).

-spec can_deliver_with_mq_down(atom(), [term()]) -> ok.
can_deliver_with_mq_down(Backend, _Config) ->
  ok = meck:new(safe_bunny_worker, [passthrough]),
  % Simulate mq is unreachable.
  meck:expect(safe_bunny_worker, deliver, fun(_, _, _, _) -> not_available end),

  BackendBin = list_to_binary(atom_to_list(Backend)),
  TestText = <<BackendBin/binary, " 4">>,

  % Queue a few messages.
  safe_bunny_helper_mq:deliver_safe(<<"test4">>, TestText),
  safe_bunny_helper_mq:deliver_safe(<<"test4">>, TestText),
  safe_bunny_helper_mq:deliver_safe(<<"test4">>, TestText),

  % Give time so deliveries are attempted.
  timer:sleep(50),

  % Restore original behavior, go go gooo
  {ok, Client2} = safe_bunny_helper_mq:start_listening(<<"test4">>, [{TestText, self()}]),
  meck:expect(safe_bunny_worker, deliver, fun(Safe, Ex, Q, P) -> meck:passthrough([Safe, Ex, Q, P]) end),
  timer:sleep(50),
  lists:foreach(fun(_) ->
    ok = receive
      {message, TestText} -> ok
    after 2000 ->
      timeout
    end
  end, lists:seq(1, 3)),
  safe_bunny_helper_mq:stop(Client2),
  true = meck:validate(safe_bunny_worker),
  ok = meck:unload(safe_bunny_worker),
  ok.

-spec can_cycle_through_poll_timers(atom(), [term()]) -> ok.
can_cycle_through_poll_timers(Backend, _Config) ->
  BackendBin = list_to_binary(atom_to_list(Backend)),
  Module = safe_bunny:consumer_module(Backend),
  TestText = <<BackendBin/binary, " 5">>,

  ok = meck:new(Module, [passthrough]),
  % Simulate local queue is down.
  Tid = ets:new(?MODULE, [public]),
  ets:insert(Tid, [{counter, 0}]),
  meck:expect(Module, next, fun(Total, State) ->
    case ets:update_counter(Tid, counter, 1) of
      R when R > 3 -> meck:passthrough([Total, State]);
      _ -> {error, some_error, State}
    end
  end),

  {ok, Client2} = safe_bunny_helper_mq:start_listening(<<"test5">>, [{TestText, self()}]),
  safe_bunny_helper_mq:deliver_safe(<<"test5">>, TestText),
  ok = receive
    {message, TestText} -> ok
  after 2000 ->
    timeout
  end,
  safe_bunny_helper_mq:stop(Client2),
  true = meck:validate(Module),
  ok = meck:unload(Module),
  ets:delete(Tid),
  ok.

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
  safe_bunny_helper_mq:Fun(<<"test3">>, TestText),
  timer:sleep(2000),
  {ok, Client1} = safe_bunny_helper_mq:start_listening(<<"test3">>, [{TestText, self()}]),
  ok = receive
    {message, TestText} -> should_have_expired
  after 1000 ->
    ok
  end,
  safe_bunny_helper_mq:stop(Client1),
  ok.
