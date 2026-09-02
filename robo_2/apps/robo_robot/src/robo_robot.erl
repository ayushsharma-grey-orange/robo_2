-module(robo_robot).

-export([start/3,run/2]).

-define(SERVER, "localhost").
-define(PORT, 5555).

start(RobotId, Current, Goal) ->
    io:format(
        "Robot ~p starting at ~p, goal: ~p~n",
        [RobotId, Current, Goal]
    ),

    {ok, Socket} = gen_tcp:connect(
        ?SERVER,
        ?PORT,
        [
            binary,
            {packet, 4},
            {active, false}
        ]
    ),

    io:format("Robot ~p connected to server~n", [RobotId]),

    Request = {register, RobotId, Current, Goal},

    gen_tcp:send(
        Socket,
        term_to_binary(Request)
    ),

    {ok, Data} = gen_tcp:recv(Socket, 0),

    Response = binary_to_term(Data),

    io:format(
        "Robot ~p received: ~p~n",
        [RobotId, Response]
    ),

    Socket.



run(Socket, RobotId) ->
    gen_tcp:send(
        Socket,
        term_to_binary({request_window, RobotId})
    ),

    {ok, Data} = gen_tcp:recv(Socket, 0),

    Response = binary_to_term(Data),

    case Response of
        {window, Positions} ->
            move_window(Socket, RobotId, Positions);

        {window_denied, Reason} ->
            io:format(
                "Robot ~p window denied: ~p~n",
                [RobotId, Reason]
            );

        Other ->
            io:format(
                "Robot ~p received unexpected response: ~p~n",
                [RobotId, Other]
            )
    end.



move_window(_Socket, _RobotId, []) ->
    ok;

move_window(Socket, RobotId, [Position | Rest]) ->
    io:format(
        "Robot ~p moving to ~p~n",
        [RobotId, Position]
    ),

    gen_tcp:send(
        Socket,
        term_to_binary(
            {moved, RobotId, Position}
        )
    ),

    {ok, Data} = gen_tcp:recv(Socket, 0),

    Response = binary_to_term(Data),

    io:format(
        "Robot ~p received: ~p~n",
        [RobotId, Response]
    ),

    case Response of
        {move_ack, Position} ->
            move_window(
                Socket,
                RobotId,
                Rest
            );

        {move_denied, Reason} ->
            io:format(
                "Move denied: ~p~n",
                [Reason]
            );

        Other ->
            io:format(
                "Unexpected response: ~p~n",
                [Other]
            )
    end.

