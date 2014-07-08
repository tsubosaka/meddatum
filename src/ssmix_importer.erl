%%
%% Copyright (C) 2013-2013 UENISHI Kota
%%
%%    Licensed under the Apache License, Version 2.0 (the "License");
%%    you may not use this file except in compliance with the License.
%%    You may obtain a copy of the License at
%%
%%        http://www.apache.org/licenses/LICENSE-2.0
%%
%%    Unless required by applicable law or agreed to in writing, software
%%    distributed under the License is distributed on an "AS IS" BASIS,
%%    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%    See the License for the specific language governing permissions and
%%    limitations under the License.
%%

-module(ssmix_importer).
-export([connect/2, disconnect/1, put_json/2,
         index_name/1,
         delete_all/2]).

-include("hl7.hrl").
-include("meddatum.hrl").
-include_lib("eunit/include/eunit.hrl").

-spec connect(term(), inet:port_number()) -> {ok, pid()}.
connect(Host, Port) ->
    riakc_pb_socket:start_link(Host, Port).

disconnect(Client) ->
    riakc_pb_socket:stop(Client).

put_json(Client, Msg) ->
    %% TODO: Bucket, Key are to be extracted from msg
    ContentType = <<"application/json">>,
    Key = hl7:key(Msg),
    Data = hl7:to_json(Msg),
    Bucket = hl7:bucket(Msg),
    RiakObj0 = meddatum:maybe_new_ro(Client, Bucket, Key, Data, ContentType),

    _ = lager:debug("inserting: ~p~n", [Key]),
    RiakObj = set_2i(RiakObj0, Msg#hl7msg.date, Msg#hl7msg.patient_id),
    case riakc_pb_socket:put(Client, RiakObj) of
      ok -> ok;
      Error -> _ = lager:error("error inserting ~p: ~p", [Key, Error])
    end.

set_2i(RiakObj0, Date, PatientID) ->
    MD0 = riakc_obj:get_update_metadata(RiakObj0),
    MD1 = riakc_obj:set_secondary_index(MD0, {{binary_index, index_name(date)}, [Date]}),
    MD2 = riakc_obj:set_secondary_index(MD1, {{binary_index, index_name(patient_id)}, [PatientID]}),
    riakc_obj:update_metadata(RiakObj0, MD2).

index_name(patient_id) ->
    "patient_id";
index_name(date) ->
    "date".

delete_all(Host, Port) ->
    delete_all(Host, Port, ?SSMIX_BUCKET),
    delete_all(Host, Port, ?SSMIX_PATIENTS_BUCKET).

delete_all(Host, Port, Bucket) ->
    Self = self(),
    DeleterPid = spawn_link(fun() -> Self ! {self(), deleter(Host, Port, Bucket)} end),
    _FetcherPid = spawn_link(fun() -> Self ! {self(), fetcher(Host, Port, DeleterPid, Bucket)} end),
    
    receive
        {_, done} ->
            receive
                {_, done} -> ok
            end
    end.

deleter(Host, Port, Bucket0) ->
    {ok, C} = connect(Host, Port),
    Bucket = meddatum:true_bucket_name(Bucket0),
    Result = deleter_loop(C, Bucket, 0),
    ok = disconnect(C),
    io:format("~p deleter: ~p~n", [Bucket, Result]),
    done.

deleter_loop(C, Bucket, Count) ->
    receive done -> {ok, Count};
            Keys when is_list(Keys) ->
            Fold = fun(Key, N) ->
                           {ok, RiakObj} = riakc_pb_socket:get(C, Bucket, Key),
                           ok = riakc_pb_socket:delete_obj(C, RiakObj, [{w,0}]),
                           N+1
                   end,
            Deleted = lists:foldl(Fold, 0, Keys),
            deleter_loop(C, Bucket, Deleted + Count)
    end.

fetcher(Host, Port, DeleterPid, Bucket0) ->
    {ok, C} = connect(Host, Port),
    Bucket = meddatum:true_bucket_name(Bucket0),
    {ok, ReqID} = riakc_pb_socket:stream_list_keys(C, Bucket),
    Result = fetcher_loop(C, ReqID, 0, DeleterPid),
    ok = disconnect(C),
    io:format("~p fetcher: ~p > ~p~n", [Bucket, ReqID, Result]),
    DeleterPid ! done,
    done.

fetcher_loop(C, ReqID, Count, DeleterPid) ->
    receive {ReqID, {keys, Keys}} ->
            DeleterPid ! Keys,
            fetcher_loop(C, ReqID, Count + length(Keys), DeleterPid);
            {ReqID, done} -> {ok, Count};
            {error, E} ->  io:format("~p", [E])
    end.


-ifdef(TEST).

-define(assertBucketName(Exp, Val),
        ?assertEqual(<<Exp/binary, ":dummyhospital">>,
                     hl7:bucket(#hl7msg{msg_type_s= Val,
                                        hospital_id= <<"dummyhospital">>}))).

bucket_name_test() ->
    ?assertBucketName(?SSMIX_PATIENTS_BUCKET, <<"ADT^A60foorbaz">>),
    ?assertBucketName(?SSMIX_BUCKET, <<"ADT^A61foobarbaz">>).

-endif.
