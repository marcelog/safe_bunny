-module(config_SUITE).

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([can_return_default/1]).

-spec all() -> [atom()].
all() -> [
  can_return_default
].

-spec init_per_testcase(term(), term()) -> void.
init_per_testcase(TestCase, Config) ->
  helper_utils:start_needed_deps(),
  application:load(safe_bunny),
  helper_utils:start(TestCase, Config).

-spec end_per_testcase(term(), term()) -> void.
end_per_testcase(_TestCase, _Config) ->
  helper_utils:stop().

-spec can_return_default([term()]) -> ok.
can_return_default(_Config) ->
  default_value = safe_bunny_config:get_option(inexistant, default_value).