-module(misc).

-include("amqp_client.hrl").

-export([setup_connection/0,
	 declare_exchanges/1,
         demo_callback/2,
         word_count_callback/2,
         word_reverse_callback/2,
         publish_msg/3]).


get_connection_params() ->
    #amqp_params_network{
		 username = <<"guest">>,
		 password = <<"guest">>,
                 virtual_host = <<"/">>,
		 host = "192.168.4.128"}.

setup_connection()->
    Amqp_params_network = get_connection_params(),
    {ok, Connection} = amqp_connection:start(Amqp_params_network),
    {ok, Channel} = amqp_connection:open_channel(Connection),
    {ok, {Connection, Channel}}.

declare_exchanges(Exchanges) ->
    {ok, {Connection, Channel}} = setup_connection(),


    [ #'exchange.declare_ok'{} = amqp_channel:call(Channel,
                                #'exchange.declare'{ exchange = Name,
                                                     type = Type,
                                                    durable = Durable}) ||
       {Name, Type, Durable} <- Exchanges ],

    amqp_channel:close(Channel),
    amqp_connection:close(Connection),
    ok.

demo_callback(_Channel, #amqp_msg{payload = Msg}) ->
  io:format("Got message ~p~n", [Msg]).

word_count_callback(_Channel, #amqp_msg{payload = Msg}) ->
  L = length(string:tokens(binary_to_list(Msg), " ")),
  io:format("Count: ~p~n", [L]).

word_reverse_callback(_Channel, #amqp_msg{payload = Msg}) ->
  Words = lists:reverse(string:tokens(binary_to_list(Msg), " ")),
  io:format("Reversed Words: ~p~n", [Words]).

publish_msg(Exchange, Msg, RKey) ->
    {ok, Connection} = amqp_connection:start(network, #amqp_params_network{}),
    {ok, Channel} = amqp_connection:open_channel(Connection),

    Publish = #'basic.publish'{exchange = Exchange, routing_key = RKey},
    amqp_channel:call(Channel, Publish, #amqp_msg{payload = term_to_binary(Msg)}),

    amqp_channel:close(Channel),
    amqp_connection:close(Connection),
    ok.
