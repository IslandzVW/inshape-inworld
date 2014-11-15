InShape data communication protocol
====================================

The InShape app locates and avatar and then sends data to the sim the avatar
is currently hosted on through an HTTP communication channel. This data is then
fed from the simulator to the scripts by means of control messages that run
through the normal chat channels that scripts listen on. This chat will appear
to the script to originate from the avatar utilizing the InShape application.

The data message is pipe delimited and is currently a string formatted as:

EXERCISE_TYPE|AVG_MAG|PULSES_PER_SECOND

EXERCISE_TYPE
-------------
The type of exercise the user is completing as enumerated below:

EXERCISE_TYPE_WALKING = 1;
EXERCISE_TYPE_RUNNING = 2;
EXERCISE_TYPE_BIKE = 3;
EXERCISE_TYPE_ROWING = 4;
EXERCISE_TYPE_STEPPER = 5;


AVG_MAG
-------
The average magnitude of the acceleration (effort) detected by the user in the
last sample window


PULSES_PER_SECOND
------------------
Exercises that InShape supports have cyclical patterns of force. When someone
is running, the foot impact on the ground produces the greates forces in the app.
Each time a foot hits the ground, a pulse is registered. Similar cyclical
force patterns appear for biking, rowing, walking, etc.


Code
---------

An example of listening for this data in LSL follows:

    integer COMMAND_CHANNEL = -129;
    integer handle;

    integer EXERCISE_TYPE_WALKING = 1;
    integer EXERCISE_TYPE_RUNNING = 2;
    integer EXERCISE_TYPE_BIKE = 3;
    integer EXERCISE_TYPE_ROWING = 4;
    integer EXERCISE_TYPE_STEPPER = 5;

    list DecodeParams(string params)
    {
        return llParseString2List(params, ["|"], []);
    }

    default
    {
        on_rez(integer param)
        {
            llResetScript();
        }

        state_entry()
        {
            handle = llListen(COMMAND_CHANNEL, "", NULL_KEY, "");
        }

        listen( integer channel, string name, key id, string message )
        {
            // If we hear anything then check it is the rider we are hearing
            // or something owned by them if we are in simulation mode
            if ((id == rider) || (SIMULATE && (llGetOwnerKey(id) == rider)))
            {
                //this is our rider talking on our command channel.
                //lets decode and make the appropriate changes
                list params = DecodeParams(message);

                //params is EXERCISE_TYPE|AVG_MAG|PULSES_PER_SECOND

            }
        }
    }
