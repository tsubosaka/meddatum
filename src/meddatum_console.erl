-module(meddatum_console).

-export([create_config/0, check_config/0,
         import_ssmix/1, import_recept/1,
         parse_ssmix/1, parse_recept/1,
         delete_all_ssmix/1, delete_recept/1]).

create_config() ->
    Filename = os:getenv("HOME")++"/.meddatum",
    case file:open(Filename, [write, exclusive]) of
        {ok, IoDevice} ->
            String =
                "[{riak_ip, \"127.0.0.1\"},\n"
                "{riak_port, 8087}].\n",
            ok = file:write(IoDevice, String),
            ok = file:close(IoDevice),
            io:format("Created ~s~n", [Filename]);
        {error, _} = E ->
            io:format("Can't create file ~s: ~p~n",
                      [Filename, E])
    end.

check_config() ->
    Filename = os:getenv("HOME")++"/.meddatum",
    case file:consult(Filename) of
        {error, Reason} ->
            io:format("~p: ~s~n", [Filename, file:format_error(Reason)]);
        {ok, _} ->
            io:format("ok~n")
    end.

import_ssmix(_) -> io:format("TBD~n").
import_recept(_) -> io:format("TBD~n").

parse_ssmix([Path]) ->
    io:setopts([{encoding,utf8}]),
    %% {ok,Path} = file:get_cwd(),
    F = fun(File, Acc0) ->
                case hl7:from_file(File, undefined) of
                    {ok, HL7Msg0} ->
                        io:format("~ts:~n", [File]),
                        io:format("~ts~n", [hl7:to_json(HL7Msg0)]);
                    {error,_} when is_list(Acc0) ->
                        [File|Acc0];
                    {error,_} ->
                        [File]
                end
        end,
    _ErrorFiles = filelib:fold_files(Path, "", true, F, []);
parse_ssmix(_) -> meddatum:help().

parse_recept([Path]) -> io:format("TBD: ~s~n", [Path]);
parse_recept(_) -> meddatum:help().
delete_all_ssmix(_) -> io:format("TBD~n").
delete_recept(_) -> io:format("TBD~n").


%% === internal ===
    %% {ok, Config} = get_config(),
    %% Host = proplists:get_value(riak_ip, Config),
    %% Port = proplists:get_value(riak_port, Config),

%% get_config() ->
%%     Filename = os:getenv("HOME")++"/.meddatum",
%%     file:consult(Filename).    
