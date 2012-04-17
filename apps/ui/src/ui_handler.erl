-module(ui_handler).
-export([init/3, handle/2, terminate/2]).

-behaviour(cowboy_http_handler).

init({tcp, http}, Req, _Opts) ->
    {ok, Req, undefined_state}.

handle(Req, State) ->
    {Method, _} = cowboy_http_req:method(Req),
    {Path, _} = cowboy_http_req:path(Req),
    io:format("ui_handler ~s ~p~n", [Method, Path]),
    try handle_request(Method, Path) of
	{ok, Status, Headers, Body} ->
	    {ok, Req2} = cowboy_http_req:reply(Status, Headers, Body, Req),
	    {ok, Req2, State}
    catch throw:{http, Status} ->
	    {ok, Req2} = cowboy_http_req:reply(Status, [], <<"Oops">>, Req),
	    {ok, Req2, State}
	  %% _:Reason ->
	  %%   io:format("Error handling ~s ~p:~n~p~n", [Method, Path, Reason]),
	  %%   {ok, Req2} = cowboy_http_req:reply(500, [], <<"Oops">>, Req),
	  %%   {ok, Req2, State}
    end.		    

terminate(_Req, _State) ->
    ok.

html_ok(Body) ->
    {ok, 200, [{<<"Content-Type">>, <<"text/html; charset=UTF-8">>}], Body}.

handle_request('GET', []) ->
    html_ok(ui_template:render_index());

handle_request('GET', [<<"~", UserName/binary>>]) ->
    html_ok(ui_template:render_user(UserName));

handle_request('GET', [<<"~", UserName/binary>>, <<Slug/binary>>]) ->
    {Path, Ext} =
	if 
	    size(Slug) > 4 ->
		case split_binary(Slug, size(Slug) - 4) of
		    {FeedSlug1, <<".", Ext1/binary>>} ->
			{FeedSlug1, Ext1};
		    _ ->
			{Slug, <<"">>}
		end;
	    true ->
		{Slug, <<"">>}
	end,
    %% PathTokens =
    %% 	tokens

    case Ext of
	<<"">> ->
	    %% All hashed episodes
	    html_ok(ui_template:render_user_feed(UserName, Path));
	<<".xml">> ->
	    %% Serve feed with hashed episodes
	    {ok, 200, [], ui_template:export_feed(UserName, Path)};
	_ ->
	    throw({http, 404})
    end;

%% TODO: 'HEAD' too
handle_request('GET', [<<"t">>, <<InfoHashHex:40/binary, ".torrent">>]) ->
    InfoHash = hex_to_binary(InfoHashHex),
    case model_torrents:get_torrent(InfoHash) of
	{ok, Name, Torrent} ->
	    Headers =
		[{<<"Content-Type">>, <<"application/x-bittorrent">>},
		 {<<"Content-Disposition">>,
		  <<"attachment; filename=", Name/binary, ".torrent">>}],
	    {ok, 200, Headers, Torrent};
	{error, not_found} ->
	    throw({http, 404})
    end;

handle_request(_Method, _Path) ->
    throw({http, 404}).
    

hex_to_binary(Hex) when is_binary(Hex) ->
    iolist_to_binary(
      hex_to_binary1(Hex));
hex_to_binary(Hex) ->
    hex_to_binary(list_to_binary(Hex)).

hex_to_binary1(<<>>) ->
    [];
hex_to_binary1(<<H1:8, H2:8, Hex/binary>>) ->
    [<<(parse_hex(H1)):4, (parse_hex(H2)):4>>
	 | hex_to_binary1(Hex)].

parse_hex(H)
  when H >= $0, H =< $9 ->
    H - $0;
parse_hex(H)
  when H >= $A, H =< $F ->
    H - $A + 16#a;
parse_hex(H)
  when H >= $a, H =< $f ->
    H - $a + 16#a;
parse_hex(_) ->
    error(invalid_hex).
