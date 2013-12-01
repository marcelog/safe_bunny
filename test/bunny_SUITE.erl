-module(bunny_SUITE).

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
  can_cycle_backends/1,
  can_deliver_safe/1,
  can_handle_no_more_backends/1
]).

-spec all() -> [atom()].
all() -> [
  can_cycle_backends,
  can_deliver_safe,
  can_handle_no_more_backends
].

-spec init_per_testcase(term(), term()) -> void.
init_per_testcase(TestCase, Config) ->
  helper_utils:start_needed_deps(),
  application:load(safe_bunny),
  {Consumers, Producers} = case TestCase of
    can_handle_no_more_backends -> {[], []};
    can_cycle_backends -> {[mysql, redis, file, ets], [mysql, redis, file, ets]};
    can_deliver_safe ->
      {ok, Mq} = application:get_env(safe_bunny, mq),
      application:set_env(safe_bunny, mq, lists:keystore(port, 1, Mq, {port, 123})),
      {[ets], [ets]};
    TestCase -> TestCase
  end,
  application:set_env(safe_bunny, consumers, Consumers),
  application:set_env(safe_bunny, producers, Producers),
  helper_utils:start(TestCase, Config).

-spec end_per_testcase(term(), term()) -> void.
end_per_testcase(_TestCase, _Config) ->
  helper_utils:stop().

-spec can_cycle_backends([term()]) -> ok.
can_cycle_backends(_Config) ->
  Mods = [
    safe_bunny_producer_mysql,
    safe_bunny_producer_redis,
    safe_bunny_producer_file,
    safe_bunny_producer_ets
  ],
  Opts = [passthrough, non_strict, non_link],
  MockWith = fun(Fun) ->
    ok = meck:new(Mods, Opts),
    ok = meck:expect(Mods, queue, Fun),
    {Pid, Ref} = helper_mq:queue(<<"test">>, <<"payload">>),
    Ret = receive
      {'DOWN', Ref, process, Pid, {spawn_failure,[{_,_,[{_,{{error,{badmatch,{error,out_of_backends}}},_,_,_}}],_}]}} -> ok
    after 1000 -> 
      timeout
    end,
    true = meck:validate(Mods),
    meck:unload(Mods),
    Ret = ok
  end,

  MockWith(fun(_) -> failed end),
  MockWith(fun(_) -> meck:exception(error, failed2) end),
  ok.

-spec can_deliver_safe([term()]) -> ok.
can_deliver_safe(_Config) ->
  ok = meck:new(safe_bunny_producer_ets, [passthrough, non_strict, non_link]),
  ok = meck:new(amqp_channel, [passthrough, non_strict, non_link]),
  ok = meck:expect(amqp_channel, call, fun(_, _, _) -> some_error end),
  ok = meck:expect(safe_bunny_producer_ets, queue, fun(_) -> ok end),
  helper_mq:deliver_safe(<<"key">>, <<"payload">>),
  timer:sleep(100),
  true = meck:validate([amqp_channel, safe_bunny_producer_ets]),
  ok = meck:unload([amqp_channel, safe_bunny_producer_ets]),
  ok.

-spec can_handle_no_more_backends([term()]) -> ok.
can_handle_no_more_backends(_Config) ->
  ok = try 
    safe_bunny:queue_task(<<"e">>, <<"k">>, <<"p">>),
    fail
  catch
    _:{badmatch, {error, out_of_backends}} -> ok;
    _:_ -> fail
  end.