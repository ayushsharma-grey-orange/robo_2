-module(robo_mnesia).

-export([
    start/0,
    add_robot/4,
    get_robot/1,
    update_robot_position/2,
    update_robot_path/2,
    get_reservation/1,
    reserve_barcode/2,
    release_barcode/1,
    get_next_window/2,
    move_robot/2,
    get_all_reservations/0,
    cleanup_robot/1
]).

-record(robot, {
    id,
    current,
    goal,
    path = []
}).

-record(reservation, {
    barcode,
    robot_id
}).


start() ->
    mnesia:create_schema([node()]),
    application:start(mnesia),

    mnesia:create_table(robot, [
        {attributes, record_info(fields, robot)},
        {disc_copies, [node()]}
    ]),

    mnesia:create_table(reservation, [
        {attributes, record_info(fields, reservation)},
        {disc_copies, [node()]}
    ]).

add_robot(RobotId, Current, Goal, Path) ->
    Robot = #robot{
        id = RobotId,
        current = Current,
        goal = Goal,
        path = Path
    },

    mnesia:transaction(fun() ->
        mnesia:write(Robot)
    end).


get_robot(RobotId) ->
    mnesia:transaction(fun() ->
        mnesia:read(robot, RobotId)
    end).


update_robot_position(RobotId, NewPosition) ->
    mnesia:transaction(fun() ->
        case mnesia:read(robot, RobotId) of
            [Robot] ->
                UpdatedRobot = Robot#robot{
                    current = NewPosition
                },

                mnesia:write(UpdatedRobot);

            [] ->
                {error, robot_not_found}
        end
    end).


update_robot_path(RobotId, Path) ->
    mnesia:transaction(fun() ->
        case mnesia:read(robot, RobotId) of
            [Robot] ->
                UpdatedRobot = Robot#robot{
                    path = Path
                },

                mnesia:write(UpdatedRobot);

            [] ->
                {error, robot_not_found}
        end
    end).

get_reservation(Barcode) ->
    mnesia:transaction(fun() ->
        mnesia:read(reservation, Barcode)
    end).


reserve_barcode(Barcode, RobotId) ->
    mnesia:transaction(fun() ->
        case mnesia:read(reservation, Barcode, write) of
            [] ->
                Reservation = #reservation{
                    barcode = Barcode,
                    robot_id = RobotId
                },

                mnesia:write(Reservation),
                ok;

            [_ExistingReservation] ->
                {error, barcode_reserved}
        end
    end).

release_barcode(Barcode) ->
    mnesia:transaction(fun() ->
        case mnesia:read(reservation, Barcode, write) of
            [] ->
                {error, barcode_not_reserved};

            [_Reservation] ->
                mnesia:delete({reservation, Barcode}),
                ok
        end
    end).

% get_next_window(RobotId, CurrentPosition) ->

get_next_window(RobotId, WindowSize) ->
    mnesia:transaction(fun() ->
        case mnesia:read(robot, RobotId, write) of
            [] ->
                {error, robot_not_found};

            [Robot] ->
                Current = Robot#robot.current,
                Path = Robot#robot.path,

                case next_positions(Current, Path, WindowSize) of
                    {ok, Positions} ->
                        case reserve_positions(Positions, RobotId) of
                            ok ->
                                {ok, Positions};

                            {error, Barcode} ->
                                {error, {barcode_reserved, Barcode}}
                        end;

                    {error, Reason} ->
                        {error, Reason}
                end
        end
    end).


next_position(Current, Path) ->
    case lists:dropwhile(
        fun(Position) -> Position =/= Current end,
        Path
    ) of
        [_Current, Next | _] ->
            {ok, Next};

        [_Current] ->
            {error, goal_reached};

        [] ->
            {error, current_position_not_in_path}
    end.


check_and_move_robot(Robot, NewPosition, Goal) ->
    RobotId = Robot#robot.id,

    case mnesia:read(reservation, NewPosition, write) of
        [{reservation, NewPosition, RobotId}] ->

            case NewPosition =:= Goal of
                true ->
                    mnesia:delete({reservation, NewPosition}),
                    mnesia:delete({robot, RobotId}),
                    {ok, goal_reached};

                false ->
                    UpdatedRobot =
                        Robot#robot{
                            current = NewPosition
                        },

                    mnesia:write(UpdatedRobot),
                    mnesia:delete({reservation, NewPosition}),

                    {ok, moved}
            end;

        [{reservation, NewPosition, OtherRobot}] ->
            {error, {position_reserved_by, OtherRobot}};

        [] ->
            {error, position_not_reserved}
    end.


next_positions(Current, Path, WindowSize) ->
    case lists:dropwhile(
        fun(Position) ->
            Position =/= Current
        end,
        Path
    ) of
        [] ->
            {error, current_position_not_in_path};

        [_Current | RemainingPath] ->
            Positions = lists:sublist(
                RemainingPath,
                WindowSize
            ),

            case Positions of
                [] ->
                    {error, goal_reached};

                _ ->
                    {ok, Positions}
            end
    end.


reserve_positions([], _RobotId) ->
    ok;

reserve_positions(
    [Barcode | Rest],
    RobotId
) ->
    case mnesia:read(reservation, Barcode, write) of
        [] ->
            Reservation = #reservation{
                barcode = Barcode,
                robot_id = RobotId
            },

            mnesia:write(Reservation),

            reserve_positions(Rest, RobotId);

        [_ExistingReservation] ->
            {error, Barcode}
    end.

% move_robot(RobotId, NewPosition) ->
%     mnesia:transaction(fun() ->
%         case mnesia:read(robot, RobotId, write) of
%             [] ->
%                 {error, robot_not_found};

%             [Robot] ->
%                 case mnesia:read(
%                     reservation,
%                     NewPosition,
%                     write
%                 ) of

%                     [{reservation, NewPosition, RobotId}] ->
%                         UpdatedRobot = Robot#robot{
%                             current = NewPosition
%                         },

%                         mnesia:write(UpdatedRobot),

%                         mnesia:delete({
%                             reservation,
%                             NewPosition
%                         }),

%                         ok;

%                     [{reservation, NewPosition, OtherRobot}] ->
%                         {error, {
%                             position_reserved_by,
%                             OtherRobot
%                         }};

%                     [] ->
%                         {error, position_not_reserved}
%                 end
%         end
%     end).

move_robot(RobotId, NewPosition) ->
    mnesia:transaction(fun() ->
        case mnesia:read(robot, RobotId, write) of
            [] ->
                {error, robot_not_found};

            [Robot] ->
                Current = Robot#robot.current,
                Goal = Robot#robot.goal,
                Path = Robot#robot.path,

                case next_position(Current, Path) of
                    {ok, NewPosition} ->
                        check_and_move_robot(
                            Robot,
                            NewPosition,
                            Goal
                        );

                    {ok, ExpectedPosition} ->
                        {error, {unexpected_position, ExpectedPosition}};

                    {error, Reason} ->
                        {error, Reason}
                end
        end
    end).


cleanup_robot(RobotId) ->
    mnesia:transaction(fun() ->
        mnesia:delete({robot, RobotId}),

        Reservations =
            mnesia:match_object(
                #reservation{
                    barcode = '_',
                    robot_id = RobotId
                }
            ),

        lists:foreach(
            fun(#reservation{barcode = Barcode}) ->
                mnesia:delete({reservation, Barcode})
            end,
            Reservations
        ),

        ok
    end).


get_all_reservations() ->
    F = fun() ->
        mnesia:match_object(#reservation{_ = '_'})
    end,
    case mnesia:transaction(F) of
        {atomic, Records} -> Records;
        {aborted, Reason} -> {error, Reason}
    end.