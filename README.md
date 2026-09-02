

open two terminals

run ./start.sh in both to start the projects

run robo_tcp_server:start().
 to make this shell wait and accept for tcp requests

in second terminal run->
    robo_robot:start(r1,Start,Goal).
    to register the robot r1 with Start and goal coordinates , eg
    S1=robo_robot:start(r1,{9,1},{9,9}).

    run robo_robot:run(S1,r1).
    this fetches a window of size 3 from the path of r1 towards its goal.
    reserves the 3 barcodes for r1 so that they may not be reserved by any other robots
    r1 executes these steps one by one, informs the robo_tcp_server. 
    robo_tcp_server receives a request getting informed about r1's movememnts
    it de-reserves the barcodes that r1 has traversed....




