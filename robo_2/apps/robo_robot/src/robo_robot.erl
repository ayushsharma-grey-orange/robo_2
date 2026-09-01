-module(robo_robot).

-export([start/3]).

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