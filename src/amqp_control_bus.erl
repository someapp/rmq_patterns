-module(amqp_control_bus).

-behaviour(gen_server).

-include("amqp_client.hrl").
-include("rmq_patterns.hrl").

-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([start/1, start_link/1]).
-export([stop/1]).

-export([start_debug/0, start_debug/1, detour_msg/5, consumer_msg/3]).

-record(state, {channel,
                control_exchange}).

%%--------------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------------

start_server(Opts) ->
    {ok, Connection} = misc:setup_connection(),
    ControlExchange = <<"control">>,
    {ok, Pid} = amqp_control_bus:start([Connection, ControlExchange, Opts]),
    io:format("Server started with Pid: ~p~n", [Pid]),
    {ok, Pid}.

%% {ok, Pid} = amqp_control_bus:start_debug().
start_debug() ->
    start_server([]).

start_debug(debug) ->
    start_server([{debug, [trace]}]).

%% amqp_control_bus:detour_msg(C, <<"detour_step_detour">>, <<"#">>, <<"detour_step_final">>, <<"">>).
%% amqp_control_bus:detour_msg(C, <<"detour_step_detour">>, <<"#">>, <<"detour_step_a">>, <<"">>).
detour_msg(Pid, InEx, InRkey, OutEx, OutRKey) ->
    send_msg(Pid, #detour_msg{in_exchange=InEx, in_rkey=InRkey,
                        out_exchange=OutEx, out_rkey=OutRKey}, <<"control.detour">>).

%% amqp_control_bus:consumer_msg(Pid, <<"my.rkey">>, {<<"my_exchange">>, <<"consumer.key">>, fun misc:word_count_callback/2}).
consumer_msg(Pid, ConsumerRKey, {Ex, RKey, Callback}) ->
  send_msg(Pid, #consumer_msg{in_exchange=Ex, in_rkey=RKey, callback = Callback}, ConsumerRKey).

send_msg(Pid, Msg, RKey) ->
    gen_server:call(Pid, {send_msg, Msg, RKey}).


start([Connection, ControlExchange, Opts]) ->
    gen_server:start(?MODULE, [Connection, ControlExchange], Opts).

start_link([Connection, ControlExchange, Opts]) ->
    gen_server:start_link(?MODULE, [Connection, ControlExchange], Opts).

stop(Pid) ->
    gen_server:call(Pid, stop, infinity).

%%--------------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------------

%% @private
init([Connection, ControlExchange]) ->
    {ok, Channel} = misc:open_channel(Connection),

    {ok, #state{channel = Channel, control_exchange = ControlExchange}}.

%% @private
handle_info(shutdown, State) ->
    {stop, normal, State}.

%% @private
handle_call({send_msg, Msg, RKey}, _From,
                #state{channel = Channel, control_exchange = Ex} = State) ->
    Publish = #'basic.publish'{exchange = Ex, routing_key = RKey},
    amqp_channel:call(Channel, Publish, #amqp_msg{payload = term_to_binary(Msg)}),
    {reply, ok, State};

%% @private
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

%%--------------------------------------------------------------------------
%% Rest of the gen_server callbacks
%%--------------------------------------------------------------------------

%% @private
handle_cast(_Message, State) ->
    {noreply, State}.

%% Closes the channel this gen_server instance started
%% @private
terminate(_Reason, #state{channel = Channel}) ->
    amqp_channel:close(Channel),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    State.
