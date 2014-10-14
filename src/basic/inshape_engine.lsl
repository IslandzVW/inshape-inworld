// Copyright 2014 InWorldz, LLC
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
// Route Runner Engine Script
//
// v2.5 Split the script into two. This is the "engine" that does the moving.
//      The other is the "pilot" that processes the input from each avatar
//      and controls their animations.
//
//      Incoming speed = exercise-type * 5 + speed
//
// v2.6 Cross-sim support
//
//----------------------------------------------------------------------------

integer DEBUG = TRUE;

integer NUM_SPEEDS = 5;

float RUN_SPEED_BEGIN = 0.25;

float INTERVAL = 0.05;

list pilotPlaces = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
list pilotSpeeds = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

// Speed is passed as type * NUM_SPEEDS + speed
// e.g. running at speed 3 = 2 * 5 + 3 = 13
// Look this up here to get the actual move size
list levels = [ 0.00, 0.00, 0.00, 0.00, 0.00,               // unknown type
                0.08, 0.12, 0.16, 0.20, RUN_SPEED_BEGIN,    // walking
                RUN_SPEED_BEGIN, 0.35, 0.45, 0.55, 0.65,    // running
                0.65, 0.68, 0.71, 0.74, 0.77,               // biking
                0.08, 0.12, 0.16, 0.20, RUN_SPEED_BEGIN,    // rowing
                0.08, 0.12, 0.16, 0.20, RUN_SPEED_BEGIN     // stepping
                ];  
                
float current_move = 0.10; // Force first calculation
float max_turn = 0.05;

integer prims;
key nc_id;
string nc_name;
integer nc_line;
key query;
list data;

integer points;
integer point;

vector move_pos;
vector move_target;
vector move_delta;
integer move_steps;

float angle;
float angle_target;
float angle_delta;
integer angle_steps;

integer anim;

Warp(vector target, rotation rot)
{
    integer s = llFloor(llVecMag(target - llGetPos()) / 10.0) + 1;
    list move = [PRIM_POSITION, target];
    if (s > 40) {
        llOwnerSay("Error : start point is around " + (string)(s * 10) + "m away - make sure you are using a route with global coordinates, or rez me closer to the start point");
        llSleep(0.5);
        llDie();
    } else {
        list moves;
        integer i;
        if (DEBUG) llOwnerSay("WARP :: " + (string)s + " steps");
        for (i=0; i<s; i++) moves += move;
        moves += [PRIM_ROTATION, rot];
        llSetPrimitiveParams(moves);
    }
}

PilotData(integer link, integer taken, integer speed)
{
    integer newdata = FALSE;
    if (llList2Integer(pilotPlaces, link) != taken)
    {
        pilotPlaces = llListReplaceList(pilotPlaces, [taken], link, link);
        newdata = TRUE;
    }
    if (llList2Integer(pilotSpeeds, link) != speed)
    {
        pilotSpeeds = llListReplaceList(pilotSpeeds, [speed], link, link);
        newdata = TRUE;
    }
    if (newdata)
    {
        AverageSpeed();
        if (DEBUG) llOwnerSay("Agent on link " + (string)link + " changed speed to " + (string)speed);
    }
}

AverageSpeed()
{
    integer pilots;
    float total;
    float average;
    integer i;
    for (i=0; i<10; i++)
    {
        if (llList2Integer(pilotPlaces, i))
        {
            pilots++;
            total += llList2Float(levels, llList2Integer(pilotSpeeds, i));
        }
    }
    if (pilots)
    {
        average = total / pilots;
    } else {
        average = 0.0;
    }
    SetLevel(average);
    if (DEBUG) llOwnerSay("AVESPEED :: " + (string)pilots + " :: " + (string)total + " :: " + (string)average);
}

NextSection()
{
    vector delta;
    float distance = 0;
    
    // Get the next target
    while (distance < current_move)
    {
        point++;
        // Check for loop
        if (point == points) point = 0;
        // Are we still okay?
        move_target = llList2Vector(data, point);
        delta = move_target - move_pos;
        distance = llVecMag(delta);
    }
}

CalcMoves()
{
    // How far to next marker?
    vector this_delta = move_target - move_pos;
    float distance = llVecMag(this_delta);

        // Calculate the number of steps
    move_steps = llFloor(distance / current_move);
    
    // Do we have at least one step?
    if (move_steps > 0)
    {
        // Calculate the move amount per step
        move_delta = this_delta / move_steps;
        
        // Calculate the angle difference
        float angle_target = llAtan2(this_delta.y, this_delta.x);
        float this_angle_delta = angle_target - angle;
        
        // Check within bounds
        if (this_angle_delta > PI) this_angle_delta -= TWO_PI;
        if (this_angle_delta < (0 - PI)) this_angle_delta += TWO_PI;
        
        // Calculate the rotation steps
        angle_steps = llAbs(llFloor(this_angle_delta / max_turn));
        
        // Ensure that it fits within the move steps
        if (angle_steps > move_steps) angle_steps = move_steps;
        
        // Calculate the angle rotation per step
        if (angle_steps > 0) angle_delta = this_angle_delta / angle_steps;

        // Report for debug
        //if (DEBUG) llOwnerSay("Move " + (string)point + " :: By " + (string)move_delta + " x " + (string)move_steps + " times :: Angle is " + (string)angle + " :: Angle change is " + (string)this_angle_delta + " :: Turn " + (string)angle_delta + " x " + (string)angle_steps + " times");
    }
}

SetLevel(float move)
{
    // If we have changed then act accordingly
    if (move != current_move)
    {
        integer starting;
        if (DEBUG) llOwnerSay("Master changed speed to " + (string)move);
        
        // Stop movement or recalculate step size etc.
        if (move == 0.0)
        {
            current_move = move;
            llSetTimerEvent(0);
            if (DEBUG) llOwnerSay("Stopping timer");
            Animate(0);
            SetVisibility();
        }
        else 
        {
            starting = (current_move == 0);
            current_move = move;
            if (move > RUN_SPEED_BEGIN)
            {
                Animate(2);
            } else {
                Animate(1);
            }
            CalcMoves();
        }


        // Start the timer if we were stationary
        if (starting) 
        {
            llSetTimerEvent(INTERVAL);
            if (DEBUG) llOwnerSay("Starting timer ...");
            SetVisibility();
        }
    }
}

SetVisibility()
{
    // Start by setting everything invisible
    llMessageLinked(LINK_SET, FALSE, "visible", NULL_KEY);
    
    // Are we stationary?
    if (current_move < 0.01)
    {
        // Are we a single prim?
        if (llGetLinkNumber() == 0)
        {
            // Yes so check the root only
            if (!llList2Integer(pilotPlaces, 0))
            {
                llMessageLinked(0, TRUE, "visible", NULL_KEY);
                return;
            }
        } else {
            // No, so check each in turn
            integer i;
            for (i=1; i<=prims; i++)
            {
                if (!llList2Integer(pilotPlaces, i))
                {
                    llMessageLinked(i, TRUE, "visible", NULL_KEY);
                    return;
                }
            }
        }
    }
}

Animate(integer pAnim)
{
    if (pAnim != anim)
    {
        llMessageLinked(LINK_SET, pAnim, "anim", NULL_KEY);
        anim = pAnim;
    }
}

default
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    state_entry()
    {
        prims = llGetNumberOfPrims();
        llMessageLinked(LINK_SET, 0, "reset", NULL_KEY);
        llSay(0, "Loading route, please wait ...");
        llMessageLinked(LINK_SET, FALSE, "visible", NULL_KEY);
        nc_name = llGetInventoryName(INVENTORY_NOTECARD, 0);
        if (nc_name == "")
        {
            nc_id = NULL_KEY;
            llSay(0, "No notecard found");
            llSetAlpha(1.0, ALL_SIDES);
        } else {
            nc_id = llGetInventoryKey(nc_name);
            nc_line = 0;
            query = llGetNotecardLine(nc_name, nc_line);
        }
    }
    
    dataserver(key query_id, string line)
    {
        if (query_id == query)
        {
            if (line == EOF)
            {
                if (DEBUG) llOwnerSay("end of notecard");
                points = llGetListLength(data);
                llSay(0, "... " + (string)points + " points loaded");
                state Ready;
            } else {
                if (DEBUG) llOwnerSay("line :: " + (string)nc_line + " :: " + (string)llGetUsedMemory() + " :: " + (string)llGetFreeMemory());
                data += llParseString2List(line, ["|"], []);
                nc_line++;
                query = llGetNotecardLine(nc_name, nc_line);
            }
        }
    }
    
    changed(integer change)
    {
        // Check for new notecard
        if ((change & CHANGED_INVENTORY) && (llGetInventoryKey(llGetInventoryName(INVENTORY_NOTECARD, 0)) != nc_id))
        {
            llResetScript();
        }
    }
}

state Ready
{
    
    on_rez(integer param)
    {
        llResetScript();
    }
    
    state_entry()
    {
        if (DEBUG) llOwnerSay("ready ...");
        move_pos = llList2Vector(data, 0);
        move_target = llList2Vector(data, 1);
        vector this_delta = move_target - move_pos;
        angle = llAtan2(this_delta.y, this_delta.x);
        if (DEBUG) llOwnerSay("warp ...");
        Warp(move_pos - llGetRegionCorner(), llEuler2Rot(<0.0,0.0,angle>));
        point = 0;
        if (DEBUG) llOwnerSay("calc ...");
        CalcMoves();
        if (DEBUG) llOwnerSay("done ...");
        current_move = 0.0;
        SetVisibility();
    }
    
    link_message(integer link, integer num, string msg, key id)
    {
        // Check for mount and dismount
        if (msg == "mount") {
            PilotData(link, TRUE, 0);
            SetVisibility();
        } else
        if (msg == "dismount") {
            PilotData(link, FALSE, 0);
            SetVisibility();
        } else
        
        // Check for incoming speed data
        if (msg == "input") {
            PilotData(link, (id != NULL_KEY), num);
        } else
        
        // Check for other message type
        {
            // Ignore for now
        }
    }
    
    changed(integer change)
    {
        // Check for new notecard
        if ((change & CHANGED_INVENTORY) && (llGetInventoryKey(llGetInventoryName(INVENTORY_NOTECARD, 0)) != nc_id))
        {
            llResetScript();
        }
    }
    
    timer()
    {
        
        // See if we still have steps or get next
        while (move_steps < 1)
        {
            NextSection();
            CalcMoves();
        }
        
        // Add the delta to get the next position
        move_pos += move_delta;
        move_steps--;
        vector p = move_pos - llGetRegionCorner();
        list acts = [PRIM_POSITION, p];
        //if (DEBUG) llOwnerSay("Steps = " + (string)move_steps);
        // Check if we are still turning and add the angle delta if so
        if (angle_steps)
        {
            angle += angle_delta;
            if (angle >= TWO_PI) angle -= TWO_PI;
            if (angle < 0.0) angle += TWO_PI;
            angle_steps--;
            acts += [PRIM_ROTATION, llEuler2Rot(<0.0,0.0,angle>)];
        }
        // Set the prim params using no delay for smoothest movement
        llSetLinkPrimitiveParamsFast(LINK_ROOT, acts);
    }
    
}
