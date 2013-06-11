-module(amqp_wiretap).

-behaviour(gen_server).

-include("amqp_client.hrl").
-include("rmq_patterns.hrl").

-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([start/1]).
-export([stop/1]).

-export([start_demo/0, start_demo/1]).

-record(state, {channel,
                in_exchange, %% exchange that we wiretap.
                in_rkey, %% ket used for the wiretap binding.
                wiretap_ctag = <<"">>, %% consumer tag for the wiretap queue
                out_exchange, %% exchange to publish the wiretap'ed messages.
                out_rkey, %% key used to publish the wiretap'ed messages.
                wt_exchange, %%
                wt_rkey, %%
                control_exchange, %% Control Bus Exchange
                control_rkey, %% key to bind to the control bus
                control_ctag}). %% consumer for the control bus queue

%%--------------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------------


demo(Opts) ->
    {ok, Connection} = amqp_connection:start(network, #amqp_params_network{}),
    ControlExchange = <<"control">>,
    ControlRKey = <<"control.wiretap">>,
    Pid = amqp_detour:start([Connection, ControlExchange, ControlRKey, Opts]),
    io:format("Server started with Pid: ~p~n", [Pid]),
    Pid.

start_demo() ->
    demo([]).

start_demo(debug) ->
    demo([{debug, [trace]}]).

%% @spec (Connection, Queue, RpcHandler) -> RpcServer
%% where
%%      Connection = pid()
%%      ProxyEx = binary()
%%      RpcHandler = binary()
%%      RpcHandler = function()
%%      RpcServer = pid()
%% @doc Starts a new RPC server instance that receives requests via a
%% specified queue and dispatches them to a specified handler function. This
%% function returns the pid of the RPC server that can be used to stop the
%% server.
start([Connection, ControlExchange, ControlRKey, Opts]) ->
    {ok, Pid} = gen_server:start(?MODULE, [Connection, ControlExchange, ControlRKey], Opts),
    Pid.

%% @spec (RpcServer) -> ok
%% where
%%      RpcServer = pid()
%% @doc Stops an exisiting RPC server.
stop(Pid) ->
    gen_server:call(Pid, stop, infinity).

%%--------------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------------

%% @private
init([Connection, ControlExchange, ControlRKey]) ->
    {ok, Channel} = misc:open_channel(Connection),
    
    {ok, ControlCTag} = amqp_utils:init_controlled_consumer(Channel, 
                            ControlExchange, ControlRKey),
    
    {ok, #state{channel = Channel, control_exchange = ControlExchange, 
                    control_rkey = ControlRKey, control_ctag = ControlCTag}}.

%% @private
handle_info(shutdown, State) ->
    {stop, normal, State};

%% @private
handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

%% @private
%% Stop to gen_server if we stop consuming from the Control Bus
handle_info(#'basic.cancel_ok'{consumer_tag = ControlCTag}, 
                #state{control_ctag = ControlCTag} = State) ->
    {stop, normal, State};

%% @private
%% Continue working if we stop consuming from a Detour Queue
handle_info(#'basic.cancel_ok'{}, State) ->
    {noreply, State};
    
%% Handles a message from the Control Bus to start "detouring"
handle_info({#'basic.deliver'{consumer_tag = ControlCTag},
             #amqp_msg{payload = Msg}},
             #state{channel = Channel, control_ctag = ControlCTag, 
                        wiretap_ctag = WTCTag} = State) ->
    
    amqp_utils:stop_consumer(WTCTag, Channel),
    
    #wiretap_msg{in_exchange = InExchange, in_rkey = InRKey, 
         out_exchange = OutExchange, out_rkey = OutRKey,
         wt_exchange = WTExchange, wt_rkey = WTRKey} = binary_to_term(Msg),

    #'queue.declare_ok'{queue = WTapQueue} 
        = amqp_channel:call(Channel, #'queue.declare'{exclusive = true, auto_delete = true}),
    QueueBind = #'queue.bind'{queue = WTapQueue, exchange = InExchange,
                                routing_key = InRKey},
    #'queue.bind_ok'{} = amqp_channel:call(Channel, QueueBind),
    #'basic.consume_ok'{consumer_tag = WTCTag2} = 
        amqp_channel:subscribe(Channel, #'basic.consume'{queue = WTapQueue, no_ack = true}, self()),

    {noreply, State#state{in_exchange = InExchange, in_rkey = InRKey, wiretap_ctag = WTCTag2,
                            out_exchange = OutExchange, out_rkey = OutRKey, 
                            wt_exchange = WTExchange, wt_rkey = WTRKey}};

%% @private
% detours a message from InExchange to OutExchange
handle_info({#'basic.deliver'{consumer_tag = WTCTag, exchange = InExchange}, Msg},
             #state{channel = Channel, out_exchange = OutExchange, out_rkey = OutRKey, 
                    wiretap_ctag = WTCTag, in_exchange = InExchange,
                    wt_exchange = WTExchange, wt_rkey = WTRKey} = State) ->
    
    Publish = #'basic.publish'{exchange = OutExchange, routing_key = OutRKey},
    amqp_channel:call(Channel, Publish, Msg),
    
    WTPublish = #'basic.publish'{exchange = WTExchange, routing_key = WTRKey},
    amqp_channel:call(Channel, WTPublish, Msg),
    
    {noreply, State}.

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
