// Copyright 2014, 2015 InWorldz, LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//----------------------------------------------------------------------------
//
// InShape Pilot Script
//
// v2.5 Split the script into two. This is the "pilot" that calculates speed
//      from the external inputs, and animates the avatar. The other is the 
//      "engine" that does the actual movement based on average speed.
//
//      Listener is now agent-specific (unless in simulation)
//      Animation is now driven by commands from engine script
//      Also added SIMULATE mode that accept input from a HUD
//
// v2.6 Tidying and commenting for general release
//
// v3.0 Largely rewritten for clarity, rezzer and optimisation
//
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
//
// Instructions for use
//
// This script receives the input signals from the InShape application, then
// converts this to an integer speed rating (0 to 5) based on parameters for
// each exercise type. This script is separated from the engine one for 
// clarity and reusability.
//
// This script is also responsible for visibility of the prim and animation
// of the avatar riding upon it.
//
// We will use link messages to send changes to exercise type and exercise
// "level", as well as sending messages to indicate whether we have a "pilot"
// or not - i.e. when someone sits on the object or gets up.
//
// Exercise types are defined as constants below, and speeds are calculated
// from the thresholds for that exercise type, resulting in a level between
// 0 and 5.
//
// Types : 1=walking, 2=running, 3=biking, 4=rowing, 5=stepping
//
// Simulator input can come from the "tech simulator", which emulates the mobile
// app and sends PPS and Mag amounts that are treated in the same way as the
// signals from the phone app would be, or from the "route test simulator"
// which allows a route creator to test their routes by selecting an exercise
// type and a level from 0 to 5 - these get passed straight to the "engine".
//
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
//
// Configuration
//
//----------------------------------------------------------------------------

// Display debug messages?
integer DEBUG = FALSE;

// Should we allow simulated input?
integer SIMULATE = TRUE;

// The channel we should listen to for pulses from the app
integer COMMAND_CHANNEL = -129;
integer CONTROLLER_CHANNEL = -1129;

// Sit position details - rotation is in degrees (euler)
vector SIT_POSITION = <0.0, 0.0, 0.01>;
vector SIT_ROTATION = <0.0, 0.0, 0.0>;

// Exercise types
integer EXERCISE_TYPE_WALKING = 1;
integer EXERCISE_TYPE_RUNNING = 2;
integer EXERCISE_TYPE_BIKE = 3;
integer EXERCISE_TYPE_ROWING = 4;
integer EXERCISE_TYPE_STEPPER = 5;

// How much weight we give the stride rate in determining final speed
float STRIDE_WEIGHT = 0.5;

// How much weight we give the avg power in determining the final speed
float POWER_WEIGHT = 0.5;

// How long a gap we will allow in input before we assume a stop
// This allows us to keep the device moving in case of a temporary
// disconnect or network glitch
integer IDLE_SECONDS_BEFORE_STOPPING = 5;

// How long before derezzing if we came from a rezzer and have np pilot
integer IDLE_BEFORE_DEREZZING = 20;

// How often to poll for missing input
float INTERVAL = 1.0;


//----------------------------------------------------------------------------
//
// Performance Configuration
//
// These variables map the PPS (pulses per second) and MAG (average magnitude)
// inputs for each exercise type to five standardised levels of input. These
// levels are then passed to the engine script.
//
//----------------------------------------------------------------------------

// PPS thresholds for each exercise type
list rates_walk = [1.0, 1.5, 2.0, 2.5, 3.0];
list rates_run = [1.0, 1.5, 2.0, 2.5, 3.0];
list rates_cycle = [0.5, 0.75, 1.0, 1.5, 2.0];
list rates_row = [0.25, 0.5, 0.75, 1.0, 1.5];
list rates_step = [1.0, 1.5, 2.0, 2.5, 3.0];

// Magnitude thresholds for each exercise type
list mags_walk = [2.6, 5.3, 10.6, 21.2, 42.4];
list mags_run = [10.0, 21.0, 42.0, 55.0, 70.0];
list mags_cycle = [1.0, 1.5, 2.4, 4.3, 9.8];
list mags_row = [0.2, 0.6, 1.0, 1.4, 3.8];
list mags_step = [0.19, 0.32, 0.64, 1.1, 3.7];

//----------------------------------------------------------------------------
//
// General variables
//
//----------------------------------------------------------------------------

integer ch_comms;

integer last_signal_time;
integer last_inactive_time;

key pilot;
integer pilot_handle;
string pilot_animation;
integer pilot_level;
integer pilot_exercise;

integer controller_handle;

list use_rates;
list use_mags;

//----------------------------------------------------------------------------
//
// Functions
//
//----------------------------------------------------------------------------

// Debug
Debug(list data)
{
    if (DEBUG) {
        llOwnerSay(llDumpList2String(["DEBUG", llGetScriptName()] + data, " :: "));
    }
}

// Process the input from the app
SignalInput(string message)
{
    Debug(["Signal", message]);
    
    // Message format is EXERCISE_TYPE|AVG_MAG|PULSES_PER_SECOND
    list params = llParseString2List(message, ["|"], []);
    integer type = llList2Integer(params, 0);
    float mag = llList2Float(params, 1);
    float pps = llList2Float(params, 2);
            
    // If we have received a zero input then stop
    if (pps == 0.0) {
        llMessageLinked(LINK_SET, 0, "STOP", NULL_KEY);
        pilot_level = 0;
        pilot_exercise = 0;
        return;
    }

    // Check for exercise type changes
    if (type != pilot_exercise) {
        
        Debug(["Exercise type changed", type]);
        
        pilot_exercise = type;

        // Check for walking exercise
        if (type == EXERCISE_TYPE_WALKING) {
            use_rates = rates_walk;
            use_mags = mags_walk;
        } else
        
        // Check for walking exercise
        if (type == EXERCISE_TYPE_RUNNING) {
            use_rates = rates_run;
            use_mags = mags_run;
        } else
        
        // Check for cycling exercise
        if (type == EXERCISE_TYPE_BIKE) {
            use_rates = rates_cycle;
            use_mags = mags_cycle;
        } else
        
        // Check for rowing exercise
        if (type == EXERCISE_TYPE_ROWING) {
            use_rates = rates_row;
            use_mags = mags_row;
        } else
        
        // Check for stepping exercise
        if (type == EXERCISE_TYPE_STEPPER) {
            use_rates = rates_step;
            use_mags = mags_step;
        } else {
            
            // Default to running
            pilot_exercise = EXERCISE_TYPE_RUNNING;
            use_rates = rates_run;
            use_mags = mags_run;
            Debug(["Unknown exercise type", type]);
        }            
        
        // Send the type to the engine script
        llMessageLinked(LINK_SET, pilot_exercise, "TYPE", NULL_KEY);
    }
        
    // Find the highest threshold levels that we meet or exceed
    // for this exercise type
    integer i;
    integer pps_level;
    integer mag_level;
    
    // For PPS :
    i = 4;
    while((i >= 0) && (!pps_level)) {
        if (pps >= llList2Float(use_rates, i)) pps_level = i + 1;
        i--;
    }
    Debug(["PPS", pps_level]);
    
    // For magnitude :
    i = 4;
    while((i >= 0) && (!mag_level)) {
        if (mag >= llList2Float(use_mags, i)) mag_level = i + 1;
        i--;
    }
    Debug(["MAG", mag_level]);
    
    // Factor in the weighting and round the total
    float pps_level_weighted = (float)pps_level * STRIDE_WEIGHT;
    float mag_level_weighted = (float)mag_level * POWER_WEIGHT;
    
    // Get the combined level
    integer level = llRound(pps_level_weighted + mag_level_weighted);
    
    // Final sanity checks in case of rounding errors
    if (level < 0) level = 0;
    if (level > 5) level = 5;
    
    // Has the level changed?
    if (level != pilot_level) {
        // Save the new level and send it to the engine script
        pilot_level = level;
        llMessageLinked(LINK_SET, level, "LEVEL", NULL_KEY);
        Debug(["COMBINED", level]);
    }    
    
    // Save the time and start (or restart) the timer
    last_signal_time = llGetUnixTime();
}

// Process the input from the app
ControllerInput(string message)
{
    Debug(["Controller", message]);
    
    // Message format is EXERCISE_TYPE|EXERCISE_LEVEL
    list params = llParseString2List(message, ["|"], []);
    integer type = llList2Integer(params, 0);
    integer level = llList2Integer(params, 1);
            
    // If we have received a zero input then stop
    if (!level) {
        llMessageLinked(LINK_SET, 0, "STOP", NULL_KEY);
        pilot_level = 0;
        pilot_exercise = 0;
        return;
    }

    // Check for level changes
    if (level != pilot_level) {
        
        Debug(["Exercise level changed", level]);
        
        pilot_level = level;
        
        // Send the type to the engine script
        llMessageLinked(LINK_SET, pilot_level, "LEVEL", NULL_KEY);
    }
        
    // Check for exercise type changes
    if (type != pilot_exercise) {
        
        Debug(["Exercise type changed", type]);
        
        pilot_exercise = type;

        // Send the type to the engine script
        llMessageLinked(LINK_SET, pilot_exercise, "TYPE", NULL_KEY);
    }
        
    // Save the time and start (or restart) the timer
    last_signal_time = llGetUnixTime();
}

// Set the camera view for the rider
SetCamera()
{

    if (llGetPermissions() & PERMISSION_CONTROL_CAMERA) {
        llSetCameraParams( [CAMERA_ACTIVE, TRUE, 
                            CAMERA_FOCUS_LOCKED, FALSE,
                            CAMERA_FOCUS_THRESHOLD, 0.05,
                            CAMERA_FOCUS_OFFSET, <0.0, 0.0, 0.5>,
                            CAMERA_PITCH, 5.0,
                            CAMERA_DISTANCE, 4.0,
                            CAMERA_BEHINDNESS_ANGLE, 0.2,
                            CAMERA_BEHINDNESS_LAG, 1.5,
                            CAMERA_POSITION_THRESHOLD, 0.3,
                            CAMERA_POSITION_LAG, 0.5]);
    }
}

// Set the animation for the rider
Animate(string anim)
{
    // If we have an avatar then change their animation if we need to
    if ((pilot != NULL_KEY) && (pilot_animation != anim)) {

        // If we have an existing animation then stop it
        if (pilot_animation != "") {
            llStopAnimation(pilot_animation);
            llSleep(0.1); // lets anim change
        }
        
        // If we have a new animation then start it
        if (anim != "") {
            llStartAnimation(anim);
        }
        
        // Save it
        pilot_animation = anim;
    }
}

// Control visibility
Visibility(integer show)
{
    if (show) {
        llSetLinkPrimitiveParamsFast(LINK_SET, [PRIM_COLOR, ALL_SIDES, <0.000, 0.384, 0.765>, 1.0]);
    } else {
        llSetLinkPrimitiveParamsFast(LINK_SET, [PRIM_COLOR, ALL_SIDES, <0.000, 0.384, 0.765>, 0.0]);
    }
}



//----------------------------------------------------------------------------
//
// Main code
//
//----------------------------------------------------------------------------


default
{
    on_rez(integer param)
    {
        ch_comms = param;
        state default;
    }
    
    state_entry()
    {
        // Unsit anyone already on us when the script starts
        if (llAvatarOnSitTarget() != NULL_KEY)
        {
            llUnSit(llAvatarOnSitTarget());
        }
        
        // Set the sit target
        rotation rot = llEuler2Rot(DEG_TO_RAD * SIT_ROTATION);
        llSitTarget(SIT_POSITION * rot, rot);
        
        // Set the object visible
        last_inactive_time = llGetUnixTime();
        Visibility(TRUE);
        
        // Set listeners if we allow simulator input
        llListen(COMMAND_CHANNEL, "", NULL_KEY, "");
        llListen(CONTROLLER_CHANNEL, "", NULL_KEY, "");
        
        // Start the timer
        llSetTimerEvent(INTERVAL);

    }
    
    listen( integer channel, string name, key id, string message )
    {
        // If we hear anything then check it is the rider we are hearing
        // or something owned by them if we are in simulation mode
        if ((id == pilot) || (SIMULATE && (llGetOwnerKey(id) == pilot)))
        {
            // What are we hearing?
            if (channel == COMMAND_CHANNEL) {
                // Process the input
                SignalInput(message);
            } else {
                ControllerInput(message);
            }
        }
    }
    
    link_message(integer sender, integer num, string msg, key id)
    {
        Debug(["Link message", msg, num, id]);
        
        // Check for animation
        if (msg == "ANIMATE")
        {
            Animate(id);
        } else
        
        // Check for reset
        if (msg == "RESET")
        {
            state default;
        }
    }

    changed(integer change)
    {
        // Check for link change
        if (change & CHANGED_LINK) {
            
            // Check for change of avatar
            key id = llAvatarOnSitTarget();
            if (id != pilot) {
                
                // Remove the chat listener if we have one
                if (pilot_handle) {
                    llListenRemove(pilot_handle);
                    pilot_handle = 0;
                }
            
                // Check whether someone got off
                if (pilot != NULL_KEY) {
                    
                    // Clear the pilot data and let the engine know
                    pilot = NULL_KEY;
                    pilot_exercise = 0;
                    pilot_level = 0;
                    pilot_animation = "";
                    last_inactive_time = llGetUnixTime();
                    llMessageLinked(LINK_SET, FALSE, "PILOT", NULL_KEY);
                    
                    // Set the object visible
                    Visibility(TRUE);
                }
                
                // Check whether someone got on
                if (id != NULL_KEY) {
                    
                    // Set up the pilot data and let the engine know
                    pilot = id;
                    pilot_exercise = 0;
                    pilot_level = 0;
                    llMessageLinked(LINK_SET, TRUE, "PILOT", pilot);
                    
                    // Request permissions
                    llRequestPermissions(pilot, PERMISSION_CONTROL_CAMERA | 
                                                PERMISSION_TRIGGER_ANIMATION);

                    // Add a user-specific listener unless we have a general one
                    if (!SIMULATE)
                    {
                        pilot_handle = llListen(COMMAND_CHANNEL, "", pilot, "");
                    }
                    
                    // Set the object invisible
                    Visibility(FALSE);
                }
                
            }
        }
    }
    
    run_time_permissions(integer perms)
    {
        if (perms & PERMISSION_CONTROL_CAMERA)
        {
            SetCamera();
        }
        if (perms & PERMISSION_TRIGGER_ANIMATION)
        {
            // Stop the standard sit
            llStopAnimation("sit");
        }
    }

    timer()
    {
        // Do we have a pilot?
        if (pilot != NULL_KEY) {

            // Are we moving?
            if (pilot_level) {
                
                // How long since the last message?
                integer unix = llGetUnixTime();
                integer since = unix - last_signal_time;
                Debug(["Check for activity timeout", since, last_signal_time, unix]);
                
                // Have we stopped getting messages
                if (since >= IDLE_SECONDS_BEFORE_STOPPING) {
                    // Slow down to a stop
                    if (pilot_level) {
                        pilot_level--;
                        Debug(["No signal, decreasing level", pilot_level]);
                        llMessageLinked(LINK_SET, pilot_level, "LEVEL", NULL_KEY);
                    } else {
                        Debug(["No signal, stopping"]);
                        llMessageLinked(LINK_SET, 0, "STOP", NULL_KEY);
                    }
                }
            
            }
            
        } else
        
        // Were we rezzed by the rezzer?
        if (ch_comms) {
            
            // How long since we became inactive?
            integer unix = llGetUnixTime();
            integer since = unix - last_inactive_time;
            Debug(["Check for rezzer timeout", since, last_inactive_time, unix]);
            
            // Should we derez?
            if (since >= IDLE_BEFORE_DEREZZING) {
                llDie();
            }
        }
    }
    
}
