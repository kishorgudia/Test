-module(city_server).

-include("../include/macros/revision.hrl").
-revision(?REVISION).

-author("Chris Whealy <chris.whealy@sap.com>").
-created("Date: 2018/02/19 17:31:51").
-created_by("chris.whealy@sap.com").

-export([
    init/3
  ]).

-include("../include/records/geoname.hrl").
-include("../include/macros/trace.hrl").


%% =====================================================================================================================
%%
%%                                                 P U B L I C   A P I
%%
%% =====================================================================================================================

%% ---------------------------------------------------------------------------------------------------------------------
init(ParentPid, Id, [City | _] = CityList) ->
  ?TRACE("Adding city ~s",[binary_to_list(City#geoname_int.name)]),
  wait_for_msg(ParentPid, Id, CityList).


%% =====================================================================================================================
%%
%%                                                P R I V A T E   A P I
%%
%% =====================================================================================================================

%% ---------------------------------------------------------------------------------------------------------------------
wait_for_msg(ParentPid, Id, CityList) ->
  receive
    %% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    %% Process commands
    {cmd, Cmd} ->
      case Cmd of
        city_list  -> ?LOG("~s", [lists:flatten([binary_to_list(C#geoname_int.name) ++ ", " || C <- CityList])]);
        city_stats -> ?LOG("City process ~c (~p) holds ~w cities", [Id, self(), length(CityList)]);
        trace_on   -> put(trace, true);
        trace_off  -> put(trace, false);
        shutdown   -> exit(normal)
      end,

      wait_for_msg(ParentPid, Id, CityList);

    %% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    %% Add new city
    {add, City} ->
      ?TRACE("Adding city ~s",[binary_to_list(City#geoname_int.name)]),
      wait_for_msg(ParentPid, Id, CityList ++ [City]);

    %% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    %% Memory usage command
    {cmd, mem_usage, RequestHandlerPid} ->
      RequestHandlerPid ! process_tools:memory_usage(self());

    %% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    %% Search city list
    %%
    %% When using regular expressions in either source code or the REPL, remember that both of these environments
    %% absorb one level of escape characters.  Therefore, regular expression metacharacters such as \s or \b must be
    %% double escaped!
    %% See the note at the top of http://erlang.org/doc/man/re.html for details
    {Ref, {search_term, Query, whole_word, WholeWord, starts_with, StartsWith}, _CountryCode, Query, CountryServerPid} ->
      ?TRACE("Searching ~w cities in ~s letter ~c for \"~s\"",[length(CityList), _CountryCode, Id, Query]),
      ?TRACE("CityList = ~s",[lists:flatten([binary_to_list(C#geoname_int.name) ++ ", " || C <- CityList])]),

      {ok, MatchPattern} = re:compile(make_reg_exp(Query, WholeWord, StartsWith),[unicode, caseless]),
      Results = [C || C <- CityList, regexp_hit(re:run(C#geoname_int.name, MatchPattern))],

      CountryServerPid ! {results, Ref, Id, Results},
      wait_for_msg(CountryServerPid, Id, CityList)
  end.


%% ---------------------------------------------------------------------------------------------------------------------
regexp_hit({match, _}) -> true;
regexp_hit(nomatch)    -> false.

%% ---------------------------------------------------------------------------------------------------------------------
%% Construct a regular expression from the parameters
%% Second parameter = "whole word" flag
%% Third parameter  = "starts with" flag
make_reg_exp(Q, true,  false) -> << <<"\\b(">>/binary, (list_to_binary(Q))/binary, <<")\\b">>/binary >>;
make_reg_exp(Q, true,  true)  -> <<   <<"^(">>/binary, (list_to_binary(Q))/binary, <<")\\b">>/binary >>;
make_reg_exp(Q, false, true)  -> <<   <<"^(">>/binary, (list_to_binary(Q))/binary, <<")">>/binary >>;
make_reg_exp(Q, false, false) -> <<    <<"(">>/binary, (list_to_binary(Q))/binary, <<")">>/binary >>.


