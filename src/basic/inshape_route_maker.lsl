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
//
// v2.7 Tidying and commenting for general release
//
// v2.8 Include 
//
// v3.0 Rewritten for clairity, performance and optimisation
//
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
//
// Instructions for use
//
// This script creates an InShape route. To use it, drop it into a prim and
// attach it to a HUD attachment point. Follow the InShape Route Maker guide
// to set up a route and for tips on creating a good user experience
//
// Version 3.0 changes :
//
// This version of the script uses more accurate ways to track turns
// and changes in height, creating better datapoints for a smoother trip.
// It also avoids previous errors that could occur on region crossings.
//
// The created route card is also far more efficient, storing corners only
// on starting and region change, and storing local coords rounded to one
// decimal place and then compressed format by removing < and > and all
// unnecessary trailing zeroes and decimals.
//
// For example,  the coordinates "<109.64160, 225.98710, 21.01696>" are 
// compressed to just "109.6,226,22" to maximise storage in the notecard.
// As a result, a notecard can store many hundreds of data points for a
// long route. It has been tested up to a six region tour with 600 points
// successfully and would probably support considerably more.
//
// The final addition in this version is to calculate an offset from the
// ground height when the recording starts so that all points are recorded
// at a standard of one meter above the ground. Future versions of the
// rezzer and devices can then adjust the route follower device for each
// user and each in-world vehicle height.
//
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
//
// Configuration
//
//----------------------------------------------------------------------------

integer DEBUG = FALSE;

float min_distance = 1.0;       // Minimum distance between points
float max_distance = 10.0;      // Maximum distance between points
float max_turn = 0.1;           // Sensitivity to turns - lower is more sensitive
float max_tilt = 0.1;           // Sensitivity to tilts - lower is more sensitive

float interval = 0.2;           // Timer interval between scans

string nc_name = "ROUTE";       // Notecard name
integer max_line_length = 250;  // The maximum length of a notecard line

//----------------------------------------------------------------------------
//
// Variables
//
//----------------------------------------------------------------------------

list data;
string line;

float total;
integer count;
integer bytes;

integer tracking;

vector sv_corner;
vector sv_local;
vector sv_global;
float sv_direction;
float sv_climb;

float mon_direction;
float mon_turn;
float mon_climb;
float mon_tilt;

string start_region;
vector start_pos;

vector offset;

//----------------------------------------------------------------------------
//
// Constants
//
//----------------------------------------------------------------------------

vector GREEN = <0.0, 1.0, 0.0>;
vector RED = <1.0, 0.0, 0.0>;
vector ORANGE = <1.0, 0.5, 0.0>;

integer DISPLAY_OFFLINE = 1;
integer DISPLAY_RECORDING = 2;
integer DISPLAY_SAVING = 3;


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

// Save a corner to the list
RecordCorner(vector corner)
{
    // Record the point
    Append(corner, 0);
    // Update the saved data points
    sv_corner = corner;
}

// Save a point to the list
RecordPoint(vector local, vector global, float direction, float climb)
{
    // Update the distance and count
    float leg = llVecDist(sv_global, global);
    total += leg;
    count++;
    Display(DISPLAY_RECORDING);
    // Record the point (adjusted to the avatar height)
    Append(local + offset, 1);
    // Update the saved data points
    sv_local = local;
    sv_global = global;
    sv_direction = direction;
    sv_climb = climb;
}

// Add the compressed vector to the output
Append(vector coords, integer decimals)
{
    // Compress the vector
    string compressed = CompressVector(coords, decimals);
    integer len = llStringLength(compressed);

    // Check we have room for it on the line
    if ((llStringLength(line) + len) >= max_line_length) {
        
        // We need a new line
        data += [line];
        line = compressed;
        bytes += len + 1;
        
    } else
    
    // Clean line?
    if (line == "") {
        
        line = compressed;
        bytes += len;
     
    // Otherwise append it   
    } else {
        
        line += "|" + compressed;
        bytes += len + 1;

    }
}

// Update the floating text
Display(integer type)
{
    string text;
    list actions;
    if (type == DISPLAY_OFFLINE) {
        text = "CLICK TO START";
        actions = [PRIM_COLOR, ALL_SIDES, RED, 1.0, PRIM_TEXT, text, RED, 1.0];
    } else
    if (type == DISPLAY_RECORDING) {
        if (DEBUG) {
            vector r = llRot2Euler(llGetRot());
            string a = CompressFloat(r.z * RAD_TO_DEG, 2);
            text = "RECORDING\n" + (string)count + " points\n" + CompressFloat(total / 1000, 3) + "km"
                + "\nBytes : " + (string)bytes
                + "\nMemory : " + (string)llGetFreeMemory()
                + "\nClimb : " + CompressFloat(mon_climb, 3)
                + "\nTilt : " + CompressFloat(mon_tilt, 3)
                + "\nDirection : " + CompressFloat(mon_direction, 3)
                + "\nTurn : " + CompressFloat(mon_turn, 3); 
        } else {
            text = "RECORDING\n" + (string)count + " points\n" + CompressFloat(total / 1000, 3) + "km"
                + "\nBytes : " + (string)bytes;
        }
        actions = [PRIM_COLOR, ALL_SIDES, GREEN, 1.0, PRIM_TEXT, text, GREEN, 1.0];
    } else
    if (type == DISPLAY_SAVING) {
        text = "Saving data, please wait ...";
        actions = [PRIM_COLOR, ALL_SIDES, ORANGE, 1.0, PRIM_TEXT, text, ORANGE, 1.0];
    }
    llSetLinkPrimitiveParamsFast(LINK_THIS, actions);
}    
    
Start()
{
    // Initialise everything
    data = [];
    count = 0;
    total = 0.0;
    tracking = TRUE;
    
    // Get the start details
    vector corner = llGetRegionCorner();
    vector local = llGetPos();
    vector global = corner + local;
    vector delta = ZERO_VECTOR;
    float direction = 0.0;
    float climb = 0.0;
    
    // Save them
    sv_corner = corner;
    sv_local = local;
    sv_global = global;
    sv_direction = direction;
    sv_climb = climb;
    
    // Save the start position
    start_region = llGetRegionName();
    start_pos = sv_local;
    
    // Set the offset based on the height from the ground
    // The offset will adjust coordinates to a standard meter
    // above the ground, regardless of the avatar height
    float ground = llGround(ZERO_VECTOR);
    float height = local.z - ground;
    float adjust = 1.0 - height;
    offset = <0.0, 0.0, adjust>;

    // Record the initial corner and position
    RecordCorner(corner);
    RecordPoint(local, global, direction, climb);
        
    llSetTimerEvent(interval);
}

Stop()
{
    tracking = FALSE;
    llSetTimerEvent(0.0);
    
    vector local = llGetPos();
    vector global = sv_corner + local;
    
    RecordPoint(local, global, sv_direction, sv_climb);
    
    Deliver();
}
    
Check()
{
    // Get the coordinates and distance from last saved
    vector corner = llGetRegionCorner();
    vector local = llGetPos();
    vector global = corner + local;
    vector delta = global - sv_global;
    float distance = llVecMag(delta);
    
    // Check we have actually moved
    if (distance >= min_distance) {
            
        // Get the climb and the difference from last saved
        float climb = delta.z / distance;
        float tilt = llFabs(climb - sv_climb);
    
        // Get the direction and difference from last saved
        vector rotv = llRot2Euler(llGetRot());
        float direction = rotv.z;
        float turn = llFabs(direction - sv_direction);
        if (turn > PI) turn = llFabs(turn - TWO_PI);

        // Keep any debug monitors
        if (DEBUG) {
            mon_climb = climb;
            mon_tilt = tilt;
            mon_direction = direction;
            mon_turn = turn;
        }
        
        // Check for a big jump, probably caused by a region crossing before
        // the region corner has updated
        if (distance > 100) {
            Debug(["Apparent jump", distance]);
            return;
        }
        
        // Check for region change
        if (corner != sv_corner) {
            Debug(["Region change detected and recorded", corner]);
            RecordCorner(corner);
            RecordPoint(local, global, direction, climb);
            return;
        }
            
        // Check for max distance
        if (distance >= max_distance) {
            Debug(["Autopoint"]);
            RecordPoint(local, global, direction, climb);
            return;
        }
        
        // Check for max turn
        if (turn >= max_turn) {
            Debug(["Detected turn", turn, direction, sv_direction]);
            RecordPoint(local, global, direction, climb);
            return;
        }
        
        // Check for max tilt
        if (tilt >= max_tilt) {
            Debug(["Detected tilt", tilt, climb, sv_climb]);
            RecordPoint(local, global, direction, climb);
            return;
        }
        
        // If we got here then nothing changed significantly, so check if we need
        // to update any debug monitor displays
        if (DEBUG) {
            Display(DISPLAY_RECORDING);
        }
    }
}

// -- Deliver the results
Deliver()
{
    // Tell the user we are saving the data
    Display(DISPLAY_SAVING);
    
    // Add last line
    data += [line];
    
    // Add info line
    string info = "@WALKRUN|" + start_region + "|" + CompressVector(start_pos, 0) + "|"
                    + (string)count + "|" + (string)llFloor(total);
    data = [info] + data;
    
    // Check we have enough points
    if (count < 10) {
        string message = "\nERROR: You must record at least 10 points to make a route";
        llDialog(llGetOwner(), message, [], 999888);
    } else {
        // Create, deliver and delete the notecard
        iwMakeNotecard(nc_name, data);
        llGiveInventory(llGetOwner(), nc_name);
        llRemoveInventory(nc_name);
    }
    
    // Clear the data array to save memory
    data = [];
    
    // Indicate that we are ready to start a new rout
    Display(DISPLAY_OFFLINE);

}

// -- Format the vector with fixed decimals to save space in the notecard
string CompressVector(vector v, integer decimals)
{
    string result = CompressFloat(v.x, decimals) + ",";
    result += CompressFloat(v.y, decimals) + ",";
    result += CompressFloat(v.z, decimals);
    return result;
}

string CompressFloat(float f, integer decimals)
{
    // Do we need decimal places?
    if (!decimals) {
        
        // if not, then just round it and return it
        return (string)llRound(f);
        
    } else {
        
        // We do need decimals
        
        // Round it to the right decimals
        float factor = llPow(10, decimals);
        string result = (string)(llRound(f * factor) / factor);
        
        // Find the decimal and truncate
        integer dp = llSubStringIndex(result, ".");
        result = llGetSubString(result, 0, dp + decimals);

        // Trim trailing zeroes
        integer stop = FALSE;
        while (!stop) {
            // Check for trailing zero and drop it
            if (llGetSubString(result, -1, -1) == "0") {
                result = llGetSubString(result, 0, -2);
            } else
            // Check for trailing decimal, drop it and stop
            if (llGetSubString(result, -1, -1) == ".") {
                result = llGetSubString(result, 0, -2);
                stop = TRUE;
            } else {
            // Must be another digit so stop
                stop = TRUE;
            }
        }
        
        // That's it, return the result
        return result;
        
        
    }
}

//----------------------------------------------------------------------------
//
// default state - pretty simple, click on and off and deliver notecard
//
//----------------------------------------------------------------------------

default
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    state_entry()
    {
        if (!llGetAttached())
        {
            llOwnerSay("I can only work as an attachment");
        } else {
            Display(DISPLAY_OFFLINE);
        }
    }
    
    touch_start(integer detected)
    {
        if (tracking) {
            Stop();
        } else {
            Start();
        }
    }
    
    timer()
    {
        Check();
    }
}