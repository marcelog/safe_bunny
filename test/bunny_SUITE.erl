-module(bunny_SUITE).

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
  can_handle_no_more_backends/1
]).

-spec all() -> [atom()].
all() -> [
  can_handle_no_more_backends
].

-spec init_per_testcase(term(), term()) -> void.
init_per_testcase(can_handle_no_more_backends, _Config) ->
  application:load(safe_bunny),
  application:set_env(safe_bunny, consumers, []),
  application:set_env(safe_bunny, producers, []),
  ok = safe_bunny:start(),
  [].

-spec end_per_testcase(term(), term()) -> void.
end_per_testcase(_TestCase, _Config) ->
  application:stop(safe_bunny),
  [].

-spec can_handle_no_more_backends([term()]) -> ok.
can_handle_no_more_backends(_Config) ->
  ok = try 
    safe_bunny:queue_task(<<"e">>, <<"k">>, <<"p">>),
    fail
  catch
    _:{badmatch, {error, out_of_backends}} -> ok;
    _:_ -> fail
  end.