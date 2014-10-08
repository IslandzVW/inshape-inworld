// Copyright 2014 InWorldz, LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Parameters

float   interval =  0.2;            // timer interval

float   step_min =  2.0;            // minimum between points

float   step_max =  20.0;           // maximum between points

float   shift_min = 4.0;            // minimum distance between direction changes

float   straight =  0.1;            // Tolerance for direction change

integer min =       5;              // minimum number of points to create notecard

vector  adjust =    ZERO_VECTOR;    // adjustment to position

string  name =      "JOURNEY";      // notecard name

integer decimals =  2;              // Number of decimal places to store

integer per_line =  5;             // How many points per notecard line


// Variables

integer attached;
integer tracking;
list l_data;
integer count;
integer on_line;
string this_line;
vector last;
vector last_saved;
vector forward = <1.0, 0.0, 0.0>;
vector last_delta_norm;

integer warned;

// Prim parameters

list on = [PRIM_COLOR, ALL_SIDES, <0.0, 1.0, 0.0>, 1.0, PRIM_TEXT, "Tracking :: 1", <0.0, 1.0, 0.0>, 1.0];
list off = [PRIM_COLOR, ALL_SIDES, <1.0, 0.0, 0.0>, 1.0, PRIM_TEXT, "Click to start", <1.0, 0.0, 0.0>, 1.0];

// Functions

// -- Check to see if we have moved far enough to register a point
Check()
{
    integer update;
    integer done;
        
    // Get the position and work out what direction (normed vector diff) we are moving in
    vector pos = llGetPos() + llGetRegionCorner();
    vector delta = (pos - last);
    float delta_mag = llVecMag(delta);
    float save_mag = llVecMag(pos - last_saved);
    
    // Did we jump too far?
    if (delta_mag >= step_max)
    {
        if (!warned)
        {
            llOwnerSay("STOP!!! You have jumped too far in one step! If you have crossed a sim then please wait a second, otherwise backtrack a little and let me catch up");
            warned = TRUE;
        }
    } else 
    // Have we travelled far enough for a step?
    if (delta_mag >= step_min)
    {
        if (warned)
        {
            llOwnerSay("Okay, I am ready again, please continue.");
            warned = FALSE;
        }
        // Get the direction and shift
        vector delta_norm = llVecNorm(delta);
        float delta_shift = llVecMag(delta_norm - last_delta_norm);
        
        // Have we changed location or direction enough to warrant a point?
        if (((delta_shift > straight) && (save_mag >= shift_min))|| (save_mag >= step_max))
        {
            count++;
            llOwnerSay((string)pos + " :: " + (string)delta_shift);
            on_line++;
            if (on_line > per_line)
            {
                on_line = 1;
                l_data += [this_line];
                this_line = FixVector(last);
            } else if (count > 2) {
                this_line += "|" + FixVector(last);
            }
            llSetText("Tracking :: " + (string)count, <0.0, 1.0, 0.0>, 1.0);
            last_delta_norm = delta_norm;
            last_saved = pos;
        }
        // Update last position
        last = pos;
    }
}

// -- Switch tracking on or off
Switch(integer ss)
{
    if (ss)
    {
        // Start tracking
        tracking = TRUE;
        last = llGetPos() + llGetRegionCorner();
        last_saved = last;
        count = 1;
        on_line = 0;
        this_line = FixVector(last);
        l_data = [];
        llSetTimerEvent(interval);
        llSetLinkPrimitiveParamsFast(LINK_THIS, on);
    } else {
        // Stop Tracking
        llSetTimerEvent(0);
        tracking = FALSE;
        llSetLinkPrimitiveParamsFast(LINK_THIS, off);

        // Add the last location and the active line
        vector pos = llGetPos() + llGetRegionCorner();
        this_line += "|" + FixVector(pos);
        l_data += [this_line];
        count++;

        // Check if we have any points for the notecard
        if (count > min)
        {
            Deliver();
        } else if (count) {
            llOwnerSay("You didn't register a long enough route to save");
            l_data = [];
        }
    }
}

// -- Deliver the results
Deliver()
{
    llOwnerSay("Saving ... please wait");

    // Create, deliver and delete the notecard
    iwMakeNotecard(name, l_data);
    llGiveInventory(llGetOwner(), name);
    llRemoveInventory(name);
    
    // Clear the data array to save memory
    l_data = [];
}

// -- Format the vector with fixed decimals to save space in the notecard
string FixVector(vector v)
{
    return "<" + llGetSubString((string)v.x, 0, -7 + decimals) 
         + "," + llGetSubString((string)v.y, 0, -7 + decimals) 
         + "," + llGetSubString((string)v.z, 0, -7 + decimals) 
         + ">"; 
}


default
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    state_entry()
    {
        Switch(FALSE);
        attached = llGetAttached();
        if (attached)
        {
            llOwnerSay("Click me to start tracking your route");
        } else {
            llOwnerSay("I can only work as an attachment");
        }
    }
    
    touch_start(integer detected)
    {
        if (attached)
        {
            Switch(!tracking);
        }
    }
    
    timer()
    {
        Check();
    }
}