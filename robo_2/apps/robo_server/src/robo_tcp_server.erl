-module(robo_tcp_server).

-export([start/0]).

-define(PORT, 5555).

-define(OBSTACLES, [{9,3},{8,3},{7,3},{7,2}]).


start() ->
    robo_mnesia:start(),
    {ok, ListenSocket} = gen_tcp:listen(
                           ?PORT,
                           [binary,
                            {packet, 4},
                            {active, false},
                            {reuseaddr, true}]),

    io:format("Server listening on port ~p~n", [?PORT]),

    accept_connections(ListenSocket).


accept_connections(ListenSocket) ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),

    io:format("New robot connected~n"),

    spawn(fun() -> handle_robot(Socket) end),

    accept_connections(ListenSocket).


handle_robot(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Data} ->
            Request = binary_to_term(Data),

            io:format("Received: ~p~n", [Request]),

            handle_request(Socket, Request),

            handle_robot(Socket);

        {error, closed} ->
            io:format("~n~nRobot disconnected~n~n"),

            gen_tcp:close(Socket)
    end.


handle_request(Socket, {hello, RobotId}) ->
    Response = {hello_ack, RobotId},

    gen_tcp:send(
      Socket,
      term_to_binary(Response));

% handle_request(Socket, {register, RobotId, Current, Goal}) ->
%     io:format(
%         "Registering robot ~p: ~p -> ~p~n",
%         [RobotId, Current, Goal]
%     ),

%     Result = robo_mnesia:add_robot(
%         RobotId,
%         Current,
%         Goal,
%         []
%     ),

%     case Result of
%         {atomic, ok} ->
%             Response = {register_ack, RobotId};

%         {aborted, Reason} ->
%             Response = {error, {registration_failed, Reason}}
%     end,

%     gen_tcp:send(
%         Socket,
%         term_to_binary(Response)
%     );

% handle_request(Socket, {request_window, RobotId}) ->
%     io:format(
%         "Robot ~p requested a window~n",
%         [RobotId]
%     ),

%     Response = {window, []},

%     gen_tcp:send(
%         Socket,
%         term_to_binary(Response)
%     );
% handle_request(Socket,
%                {moved, RobotId, NewPosition}) ->
%     io:format(
%       "Robot ~p moved to ~p~n",
%       [RobotId, NewPosition]),

%     case robo_mnesia:move_robot(
%            RobotId,
%            NewPosition) of

%         {atomic, ok} ->
%             Response = {move_ack,
%                         NewPosition};

%         {atomic, {error, Reason}} ->
%             Response = {move_denied,
%                         Reason};

%         {aborted, Reason} ->
%             Response = {error,
%                         {database_error, Reason}}
%     end,

%     gen_tcp:send(
%       Socket,
%       term_to_binary(Response));

handle_request(Socket, {moved, RobotId, NewPosition}) ->
    io:format(
        "Robot ~p moved to ~p~n",
        [RobotId, NewPosition]
    ),

    case robo_mnesia:move_robot(RobotId, NewPosition) of
        {atomic, {ok, moved}} ->
            Response = {move_ack, NewPosition};

        {atomic, {ok, goal_reached}} ->
            io:format(
                "Robot ~p reached its goal.~n",
                [RobotId]
            ),
            Response = {goal_reached, NewPosition};

        {atomic, {error, Reason}} ->
            Response = {move_denied, Reason};

        {aborted, Reason} ->
            Response = {error, {database_error, Reason}}
    end,

    gen_tcp:send(Socket, term_to_binary(Response));
handle_request(Socket, {request_window, RobotId}) ->
    io:format(
      "Robot ~p requested a window~n",
      [RobotId]),

    case robo_mnesia:get_next_window(RobotId, 3) of
        {atomic, {ok, Positions}} ->
            io:format(
              "Reserved window for ~p: ~p~n",
              [RobotId, Positions]),

            Response = {window, Positions};

        {atomic, {error, Reason}} ->
            io:format(
              "Window denied for ~p: ~p~n",
              [RobotId, Reason]),

            Response = {window_denied, Reason};

        {aborted, Reason} ->
            Response = {error,
                        {database_error, Reason}}
    end,

    gen_tcp:send(
      Socket,
      term_to_binary(Response));
handle_request(Socket, {register, RobotId, Current, Goal}) ->
    io:format(
      "Registering robot ~p: ~p -> ~p~n",
      [RobotId, Current, Goal]),

    Obstacles = ?OBSTACLES,

    case robo_pathfinder:find_path(
           Current,
           Goal,
           Obstacles) of
        {ok, Path} ->
            io:format(
              "Path for ~p: ~p~n",
              [RobotId, Path]),

            Result = robo_mnesia:add_robot(
                       RobotId,
                       Current,
                       Goal,
                       Path),

            case Result of
                {atomic, ok} ->
                    Response = {register_ack, RobotId};

                {aborted, Reason} ->
                    Response = {error,
                                {registration_failed, Reason}}
            end;

        {error, no_path} ->
            Response = {error,
                        no_path}
    end,

    gen_tcp:send(
      Socket,
      term_to_binary(Response));
% handle_request(Socket, {moved, RobotId, Barcode}) ->
%     io:format(
%         "Robot ~p moved to ~p~n",
%         [RobotId, Barcode]
%     ),

%     Response = {move_ack, Barcode},

%     gen_tcp:send(
%         Socket,
%         term_to_binary(Response)
%     );

handle_request(Socket, Request) ->
    Response = {error, {unknown_request, Request}},

    gen_tcp:send(
      Socket,
      term_to_binary(Response)).
