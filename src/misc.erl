-module(misc).

-include("amqp_client.hrl").

-export([declare_exchanges/1,
         demo_callback/2,
         word_count_callback/2,
         word_reverse_callback/2,
         publish_msg/3]).

declare_exchanges(Exchanges) ->
    {ok, Connection} = amqp_connection:start(#amqp_params_network{}),
    {ok, Channel} = amqp_connection:open_channel(Connection),

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
