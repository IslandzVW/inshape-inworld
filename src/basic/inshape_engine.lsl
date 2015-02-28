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
// InShape Engine Script
//
// v2.5 Split the script into two. This is the "engine" that does the moving.
//      The other is the "pilot" that processes the input from each avatar
//      and controls their animations.
//
//      Incoming speed = exercise-type * 5 + speed
//
// v2.6 Cross-sim support
//
// v2.7 Tidying and commenting for general release
//
// v2.8 Use new notecard format and further tuning
//
// v3.0 Rewritten for clarity, rezzer and optimisation
//
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
//
// Instructions for use
//
// This is the "engine" script for the InShape route follower. It takes a set
// of coordinates from a notecard and input from the "pilot" script to move
// the device around a circuit that has been created by the InShape Routemaker.
//
// The route file will be one of two formats :
//
// v2 format was a simple list of global coordinates, i.e. the corner coords
// of the region plus the local coordinates
//
// v3 format was created to allow for more datapoints but highly compressed so
// as to allow for much longer routes. Region corners are only recorded on the
// initial step and on region crossings. All other points are stored as local
// coordinates only. The coordinates are further compressed by rounding to one
// decimal place then removing all unnecessary characters. For example the
// coordinates "<109.64160, 225.98710, 21.01696>" are compressed to "109.6,226,22"
// which saves a lot of space. This script then adds the < and > brackets again.
//
// The notecard contains some header information containing the route type, point
// cant and total distance.
//
// The signal from the "pilot" script is an exercise "type" or a "level" which
// is derived from the "pulses per second" and "magnitude" signals sent to the 
// "pilot" script by the mobile application. The level can be from 0 to 5, 
// where zero means that the mobile app is either not sending signals, or is
// sending values below the minimum threshold for that exercise type.
//
// This script is designed to work on various route types (WALKRUN, CYCLE
// and ROW) and various real-life devices. Someone on an exercise cycle in
// real-life might well choose a CYCLE route and would watch their avatar
// cycling in InWorldz, moving faster or slower, depending on their effort
// in real-life. However, they could also choose to follow a ROW route in
// which case their avatar will be rowing a boat around a water route. In
// this case their increased effort is translated to faster boat movement.
//
// In order to keep the motion stable, and respect the vision of the route
// creator, the speed of motion is based on the exercise level (0 to 5)
// and a set of speeds for the route type, NOT the real-life exercise type.
// In other words, someone flat-out on a real-life cycle will move a boat
// at the same speed as someone flat-out on a real-life rowing machine.
// The one exception to this rule is someone walking in real-life on an
// in-world WALKRUN course. They will move more slowly and use mostly 
// walking animations rather than running ones.
//
// This device will delete any existing route when it starts or is rezzed, to
// prevent errors trying to reach start coordinates in a different region. If
// the device is rezzed by the rezzer, it will request the route notcard from
// the rezzer device, otherwise it will ask the owner to add a route notecard.
// In either case, once it has a route notecard it will read it and jump to
// the route start, ready to be used.
//
// To prevent clutter, the "pilot" script autodeletes the object when it is
// not in use.
//
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
//
// Configuration
//
//----------------------------------------------------------------------------

// Display debug messages?
integer DEBUG = FALSE;

// The timer interval for movement
float interval = 0.05;

// The minimum distance for each calculation
float min_distance = 0.6;

// Maximum turn - keeps things smooth
float max_turn = 0.01;

// The speeds for different route/device type and level
list speeds_walk = [0.00, 0.08, 0.12, 0.16, 0.20, 0.25];
list speeds_run = [0.00, 0.25, 0.35, 0.45, 0.55, 0.65];
list speeds_cycle = [0.00, 0.65, 0.68, 0.71, 0.74, 0.77];
list speeds_row = [0.00, 0.08, 0.12, 0.16, 0.20, 0.25];

// The animations for different route/device type and level
list anims_walk = ["", "Walk", "Walk", "Walk", "Walk", "Run"];
list anims_run = ["", "Walk", "Run", "Run", "Run", "Run"];
list anims_cycle = ["", "", "", "", "", ""];
list anims_row = ["", "", "", "", "", ""];
                
//----------------------------------------------------------------------------
//
// Constants
//
//----------------------------------------------------------------------------

integer EXERCISE_TYPE_WALKING = 1;
integer EXERCISE_TYPE_RUNNING = 2;
integer EXERCISE_TYPE_BIKE = 3;
integer EXERCISE_TYPE_ROWING = 4;
integer EXERCISE_TYPE_STEPPER = 5;

//----------------------------------------------------------------------------
//
// Variables
//
//----------------------------------------------------------------------------

integer ch_comms;

list use_speeds;
list use_anims;

string  nc_name;
integer nc_line;
key     nc_query;

key     pilot;
integer pilot_active;
integer pilot_exercise;
integer pilot_level;
string  pilot_animation;
float   pilot_speed;

list    data;

integer points;
integer point;
vector  corner;

vector  current_corner;
vector  current_global;
float   current_angle;

vector  target_corner;
vector  target_global;
float   target_angle;
integer target_steps;
integer target_angle_steps;

vector  delta_movement;
float   delta_angle;

integer turn_now;

string  route_type;
integer keep_level;

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

// Initialise
Init()
{
    // Stop the timer
    llSetTimerEvent(0.0);
    
    // Instruct the pilot script to reset
    llMessageLinked(LINK_SET, 0, "RESET", NULL_KEY);
        
    // Clear the data and reset the variables
    data = [];
    point = 0;
    pilot = NULL_KEY;
    pilot_exercise = 0;
    pilot_level = 0;
    pilot_speed = 0.0;
    pilot_animation = "";
    route_type = "";
}

// Send the animation to the pilot script
Animate()
{
    string anim = llList2String(use_anims, pilot_level);
    if (anim != pilot_animation) {
        llMessageLinked(LINK_SET, 0, "ANIMATE", anim);
        pilot_animation = anim;
        Debug(["Animating", anim]);
    }
}

// Process input from the pilot script
Input(key id, string msg, integer num)
{
    // Check for change of exercise type
    if (msg == "TYPE") {
        pilot_active = TRUE;
        SetExerciseType(num);
    } else

    // Check for change of exercise level
    if (msg == "LEVEL") {
        pilot_active = TRUE;
        SetExerciseLevel(num);
    } else
    
    // Check for exercise stop
    if (msg == "STOP") {
        pilot_active = FALSE;
        Stop();
    }
    
    // Check for pilot change
    if (msg == "PILOT") {
        if (num) {
            pilot = id;
            Status("", "white");
        } else {
            Stop();
            pilot = NULL_KEY;
            Status("Click me to resume this route", "white");
        }
    }
}

SetRouteType(string type)
{
    route_type = type;
    // Set properties for route type
    if (route_type == "WALKRUN") {
        keep_level = TRUE;
    } else
    if (route_type == "CYCLE") {
        keep_level = FALSE;
    } else
    if (route_type == "ROW") {
        keep_level = TRUE;
    }
}

// Change the exercise type
SetExerciseType(integer type)
{
    Debug(["Setting type", type, route_type]);
    
    pilot_exercise = type;
    // Configure based on route type and exercise type as appropriate
    if (route_type == "WALKRUN") {
        // On a walk/run route, use run speeds and anims unless the
        // pilot's activity is walking, in which case use walk data
        if (pilot_exercise == EXERCISE_TYPE_WALKING) {
            use_speeds = speeds_walk;
            use_anims = anims_walk;
        } else {
            use_speeds = speeds_run;
            use_anims = anims_run;
        }
    } else
    if (route_type == "CYCLE") {
        // On a cycle route, use the same speeds and anims for all
        // pilot activities
        use_speeds = speeds_cycle;
        use_anims = anims_cycle;
    } else
    if (route_type == "ROW") {
        // On a rowing route, use the same speeds and anims for all
        // pilot activities
        use_speeds = speeds_row;
        use_anims = anims_row;
    }
    
    // Get the speed (distance per step) for this level and route type
    pilot_speed = llList2Float(use_speeds, pilot_level);
    Debug(["Speed for level", pilot_level, pilot_speed] + use_speeds);
    
    // As we have reset the type of exercise, recalculate the movement
    Calculate();
    
    // Send the appropriate animation name to the pilot
    Animate();
}

// Change the exercise level
SetExerciseLevel(integer level)
{
    // Check whether we are moving (level > 0)
    if (level) {
        // We have activity, so recalculate the movement
        pilot_level = level;
        Debug(["Setting level", pilot_level]);
        
        // Get the speed (distance per step) for this level and route type
        pilot_speed = llList2Float(use_speeds, pilot_level);
        Debug(["Speed for level", pilot_level, pilot_speed] + use_speeds);
        
        // Recalculate this leg of the journey
        Calculate();
        
    } else {
        
        // We have no activity, so stop
        Stop();
    }
    // Send the appropriate animation name to the pilot
    Animate();
}

// Get the next route point
Next()
{
    list coord_list;
    vector coord_corner;
    vector coord_local;

    // We need to allow for v2 format (all globals) and v3 
    // format (corner|local|local) so that both work
    
    // Run through points until we find a local coordinate
    // picking up the corner changes on the way
    while (coord_local == ZERO_VECTOR) {
        
        // Increment the point number, looping at end
        point = (point + 1) % points;
    
        // Break down the coordinates
        coord_list = Coords(llList2String(data, point));
        coord_corner = llList2Vector(coord_list, 0);
        coord_local = llList2Vector(coord_list, 1);

        // Check for corner
        if (coord_corner != ZERO_VECTOR) {
            target_corner = coord_corner;
        }
    }

    // We have a local coordinate and any corner updates    
    target_global = target_corner + coord_local;
    Debug(["Next corner and local", target_corner, coord_local]);
}

// Work out the movement data for the current target
Calculate()
{
    // Stop the timer
    llSetTimerEvent(0.0);
    
    // If we are not moving then exit
    if (pilot_speed < 0.01) {
        Stop();
        return;
    }

    // Get the distance to the target and how many steps that is
    vector target_delta = target_global - current_global;
    float distance = llFabs(llVecMag(target_delta));
    //target_steps = llRound(distance / pilot_speed);

    // Are we too close to the next point to make it worth it?
    while ((target_steps < 2) || (distance < min_distance)) {
        // Get the next point
        Next();
        target_delta = target_global - current_global;
        distance = llFabs(llVecMag(target_delta));
        target_steps = llRound(distance / pilot_speed);
    }

    Debug(["Point", point, "Target delta", target_delta, "Distance", distance, "Steps", target_steps]);
    
    // Work out the actual vector movement for each step
    delta_movement = target_delta / target_steps;
    Debug(["Delta movement", delta_movement]);

    // Work out the new angle
    target_angle = llAtan2(target_delta.y, target_delta.x);
    float turn = target_angle - current_angle;
    if (turn > PI) turn -= TWO_PI;
    if (turn < (0 - PI)) turn += TWO_PI;

    // Check for the turn_now flag which indicates that the
    // route is starting and we want to just turn now
    if (turn_now) {
        
        // Make sure we don't do this again
        turn_now = FALSE;
        
        // Immediately turn to the target angle
        current_angle = target_angle;
        target_angle_steps = 0;
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [PRIM_ROTATION, llEuler2Rot(<0.0, 0.0, target_angle>)]);
        Debug(["Turn now", current_angle]);
        
    } else {
    
        // Smooth the turn into tiny increments for comfort    

        // Divide the angle into steps according to max turn
        target_angle_steps = llCeil(llFabs(turn / max_turn));
    
        // Ensure that we can turn within the movement steps
        if (target_angle_steps > target_steps) {
            target_angle_steps = target_steps;
        }
        
        // Divide the turn by the number of steps
        delta_angle = turn / target_angle_steps;
        Debug(["Smooth angle", current_angle, target_angle, turn, target_angle_steps]);
        
    }

    // Check we are actually moving
    if (pilot_speed < 0.01) {
        // Stop if not
        Stop();
    } else {
        // Start the timer
        llSetTimerEvent(interval);
    }
    
}

// Move the device
Move()
{
    // Find my current location
    vector my_corner = llGetRegionCorner();
    vector my_global = my_corner + llGetPos();
    
    // Find my next position
    vector next_global = current_global + delta_movement;
    
    // Make sure it is close - which avoids problems with region crossings
    // It will just keep trying to find the next point until the region
    // corner catches up
    if (llFabs(llVecDist(next_global, my_global)) < 20.0) {
        
        // Set up the change list
        list changes;
        
        // Work out the next position
        changes += [PRIM_POSITION, next_global - my_corner];
        
        // Check for a rotation
        if (target_angle_steps) {
            current_angle += delta_angle;
            if (current_angle > PI) current_angle -= TWO_PI;
            if (current_angle < (0 - PI)) current_angle += TWO_PI;
            changes += [PRIM_ROTATION, llEuler2Rot(<0.0, 0.0, current_angle>)];
            target_angle_steps--;
        }
            
        // Apply the changes    
        llSetLinkPrimitiveParamsFast(LINK_ROOT, changes);
        
        // Save the data
        current_corner = my_corner;
        current_global = next_global;
        
        // Count down the steps
        target_steps--;
        
    }
}

// Stop the movement
Stop()
{
    // Stop the timer
    llSetTimerEvent(0.0);

    // Set the level to zero
    pilot_level = 0;
    pilot_speed = 0.0;
    
    // Send the animation instruction
    Animate();
}

// Convert a coordinate
list Coords(string in)
{
    // returns [corner, local]

    // Check whether we need to add angle brackets (v3)
    if (llGetSubString(in, 0, 0) != "<") {
        in = "<" + in + ">";
    }
    
    // Break it up into corner and local
    vector v = (vector)in;
    float cx = llFloor(v.x / 256.0);
    float cy = llFloor(v.y / 256.0);
    vector corner = <cx, cy, 0.0> * 256;
    vector local = v - corner;
    return [corner, local];
}

// Jump to a position - used to send the object to the starting location
Warp(vector target)
{
    integer i;
    integer n = llFloor(llVecMag(target - llGetPos()) / 10.0) + 1;
    list actions;
    for (i=0; i<=n; i++) {
        actions += [PRIM_POSITION, target];
    }
    llSetPrimitiveParams(actions);
}

// Set the floating text
Status(string text, string colorname)
{
    llSetText(text, iwNameToColor(colorname), 1.0);
}

//----------------------------------------------------------------------------
//
// Default state - loads the notecard
//
//----------------------------------------------------------------------------

default
{
    on_rez(integer param)
    {
        // Store the rezzer channel, if we have one
        ch_comms = param;
        // Clear any existing notecard
        llRemoveInventory(llGetInventoryName(INVENTORY_NOTECARD, 0));
        // Restart the script (with resetting)
        state default;
    }
    
    changed(integer change)
    {
        // Check for inventory changes
        if (change & CHANGED_INVENTORY) {
            state default;
        }
    }
    
    state_entry()
    {
        // Initialise
        Init();
        
        // Check for a notecard (we won't have one if we were just rezzed)
        if (llGetInventoryNumber(INVENTORY_NOTECARD) == 1) {
            
            // Set the visible status
            Status("Reading, please wait ...", "orange");

            // We have a notecard, so start reading it
            nc_name = llGetInventoryName(INVENTORY_NOTECARD, 0);
            nc_line = 0;
            nc_query = llGetNotecardLine(nc_name, nc_line);
            
        } else {
            

            // Set the visible status
            Status("Awaiting route, please wait ...", "red");
            
            // Check if we were rezzed from a rezzer device and request
            // the route notecard accordingly
            if (ch_comms) {
                // We were, so request the notecard from the rezzer
                llWhisper(ch_comms, "NCREQUEST");
            } else {
                // We must have been rezzed by the owner for testing
                llWhisper(0, "Please add the route notecard to my contents to get started");
            }
            
        }
    }

    dataserver(key query_id, string line)
    {
        // Check this is our notecard query
        if (query_id == nc_query) {
            
            // Clear the key - always good practice
            nc_query = NULL_KEY;
            
            // Have we reached the end?
            if (line == EOF) {
                // We have finished reading the notecard, so move on
                Debug(["End of notecard"]);
                points = llGetListLength(data);
                state Prepare;
            } else
            
            // Is this a comment line?
            if (llGetSubString(line, 0, 0) == "@") {
                // This is the info
                list parts = llParseString2List(line, ["@", "|"], []);
                route_type = llList2String(parts, 0);
                Debug(["Route type", route_type]);
                nc_line++;
                nc_query = llGetNotecardLine(nc_name, nc_line);
            } else {
                
                // This is a valid data line, so store the data
                Debug(["NC Line", nc_line, llGetFreeMemory()]);
                data += llParseString2List(line, ["|"], []);
                
                // Read the next line
                nc_line++;
                nc_query = llGetNotecardLine(nc_name, nc_line);
            }
        }
    }
    
}


//----------------------------------------------------------------------------
//
// Prepare state - move to the start and get ready for the first stage
//
//----------------------------------------------------------------------------

state Prepare
{
    
    on_rez(integer param)
    {
        // Store the rezzer channel, if we have one
        ch_comms = param;
        // Clear any existing notecard
        llRemoveInventory(llGetInventoryName(INVENTORY_NOTECARD, 0));
        // Restart the script (with resetting)
        state default;
    }
    
    changed(integer change)
    {
        // Check for inventory changes
        if (change & CHANGED_INVENTORY) {
            state default;
        }
    }

    state_entry()
    {
        // Initialise
        string error;
        current_corner = ZERO_VECTOR;
        point = -1;
        
        // Set the visible status
        Status("Preparing, please wait ...", "orange");

        // Get the first corner and first point
        list coord_list;
        vector coord_corner;
        vector coord_local;
        
        // We need to allow for v2 format (all globals) and v3 
        // format (corner|local|local) so that both work
        
        // Run through points until we find a local coordinate
        // picking up the corner changes on the way
        while (coord_local == ZERO_VECTOR) {
            
            // Increment the point number, looping at end
            point = (point + 1) % points;
        
            // Break down the coordinates
            coord_list = Coords(llList2String(data, point));
            coord_corner = llList2Vector(coord_list, 0);
            coord_local = llList2Vector(coord_list, 1);
    
            // Check for corner
            if (coord_corner != ZERO_VECTOR) {
                current_corner = coord_corner;
            }
        }
    
        // Check for v2 notecard (first point was global)
        if (point < 1) {
            // v2 had no route type
            route_type = "WALKRUN";
        }
            
        // Check for errors
        
        // Check we have a route type
        if (route_type == "") {
            error = "Invalid route notecard, no route type found";
        } else

        // Check we have data
        if (points < 10) {
            error = "Invalid route notecard, must have at least 10 points";
        } else

        // Check it is actually a corner
        if (current_corner.x < 300) {
            error = "Invalid route notecard, does not start with a corner";
        } else
        
        // Check we are in the right region to start the route
        if (current_corner != llGetRegionCorner()) {
            error = "This route does not start in this region";
        }
        
        // Check for errors
        if (error != "") {
            
            // Report the error in chat
            llWhisper(0, error);
            
            // Check if we were rezzed from a rezzer
            if (ch_comms) {
                // This is from a rezzer, so kill it
                llDie();
            } else {
                // This was manually rezzed, so remove the route
                // notecard and let it reset
                llRemoveInventory(nc_name);
            }
            
        } else {

            // Work out the global start position and move to it
            current_global = current_corner + coord_local;
            Warp(coord_local);

            // Set the calculation to turn now
            turn_now = TRUE;

            // Set the target to be the current position to force
            // the calculation to get the next pount
            target_corner = current_corner;
            target_global = current_global;
            target_steps = 0;
    
            // Ready to go
            state Ready;        
            
        }
    }
    
}


//----------------------------------------------------------------------------
//
// Ready state - moves the object around the route
//
//----------------------------------------------------------------------------

state Ready
{
    
    on_rez(integer param)
    {
        // Store the rezzer channel, if we have one
        ch_comms = param;
        // Clear any existing notecard
        llRemoveInventory(llGetInventoryName(INVENTORY_NOTECARD, 0));
        // Restart the script (with resetting)
        state default;
    }
    
    changed(integer change)
    {
        // Check for inventory changes
        if (change & CHANGED_INVENTORY) {
            state default;
        }
    }
    
    state_entry()
    {
        // Set the visible status
        Status("Click me to get started", "white");
    }
    
    link_message(integer link, integer num, string msg, key id)
    {
        Debug(["Link message", msg, num, id]);
        
        // Process the input
        Input(id, msg, num);
        
    }
    
    timer()
    {
        // Get the next position if we need one
        while (target_steps < 1)
        {
            Calculate();
        }
        
        // Move the object
        Move();
    }
    
}
