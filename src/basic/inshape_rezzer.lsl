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
// InShape Rezzer
//
// v3.0 A device to rez the route follower "vehicles" for InShape routes
//
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
//
// Instructions for use
//
// This script selects a random channel for itself then waits for a notecard
// to be added to its contents. It then reads the first line of the notecard
// to determine the type of route it contains and changes the sign texture
// and hover text accordingly.
//
// On being clicked, it rezzers the appropriate route follower device and
// waits for the device to request the notecard, upon which it passes that
// notecard to the device to initialise it.
//
// Future suggestions :
//  detect the avatar height and adjust the "runner" height accordingly
//  automatically submit start location and type to a web service
//
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
//
// Configuration
//
//----------------------------------------------------------------------------

// Display debug messages?
integer DEBUG = FALSE;

// The texture and device names for each route type
list type_data = [  "WALKRUN", "InShape Runner", "887b71ec-1162-4ee6-bfed-35ebaa942aa5",
                    "CYCLE", "InShape Cycle", "f967259b-b5e5-4d35-9d28-78cf48127816",
                    "ROW", "InShape Boat", "61dbe8be-0e88-43f9-b95b-4aba1b474386"   ];
                    
integer channel_base = -372670000;
integer channel_range = 10000;

//----------------------------------------------------------------------------
//
// General variables
//
//----------------------------------------------------------------------------

integer ch_comms;

string route_type;
string vehicle;
key sign;

string nc_name;
key query;


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


// Set text and color
Status(string text, string color_name)
{
    vector color = iwNameToColor(color_name);
    llSetLinkPrimitiveParamsFast(LINK_ROOT, [
        PRIM_COLOR, 2, color, 1.0,
        PRIM_COLOR, 4, color, 1.0,
        PRIM_COLOR, 5, color, 1.0,
        PRIM_TEXT, text, color, 1.0 ]);
}


//----------------------------------------------------------------------------
//
// State default - look for a notecard
//
//----------------------------------------------------------------------------


default
{
    on_rez(integer param)
    {
        // Remove any existing route notecard
        if (nc_name != "") llRemoveInventory(nc_name);
        // Reset the script
        llResetScript();
    }

    changed(integer change)
    {
        // Reset on changed inventory
        if (change & CHANGED_INVENTORY) {
            llResetScript();
        }
    }
    
    state_entry()
    {
        // Set the visual status
        Status("Initialising ...", "black");
        
        // Check for route notecard
        if (llGetInventoryNumber(INVENTORY_NOTECARD) == 1) {
            
            // We have one, so check it
            Status("Loading ...", "orange");
            nc_name = llGetInventoryName(INVENTORY_NOTECARD, 0);
            query = llGetNotecardLine(nc_name, 0);
            
        } else {
            
            // No route notecard
            Status("Please add a route notecard", "red");
            
        }
    }
        
    dataserver(key query_id, string data)
    {
        // Is this our notecard query?
        if (query_id == query) {
            
            query = NULL_KEY; // Always good practice
            
            // Check we have a line
            if (data == EOF) {
                Debug(["Empty route file"]);
                llOwnerSay("This isn't a valid route notecard");
                llRemoveInventory(nc_name);
                llResetScript();
            }
            
            // Check it is a valid format
            string first = llGetSubString(data, 0, 0);
            if ((first != "<") && (first != "@")) {
                Debug(["First character error", first]);
                llOwnerSay("This isn't a valid route notecard");
                llRemoveInventory(nc_name);
                llResetScript();
            }
            
            // Get the route type
            if (first == "@") {
                // v3 route
                list parts = llParseString2List(data, ["@", "|"], []);
                Debug(["v3 route"] + parts);
                route_type = llList2String(parts, 0);
            } else {
                Debug(["23 route"]);
                route_type = "WALKRUN";
            }
            
            // Find the relevant data for the route type
            integer p = llListFindList(type_data, [route_type]);
            if (p > -1) {
                vehicle = llList2String(type_data, p + 1);
                sign = llList2Key(type_data, p + 2);
            } else {
                Debug(["Unknown route type", route_type]);
                llOwnerSay(route_type + " isn't a valid route type");
                llRemoveInventory(nc_name);
                llResetScript();
            }
            
            // Check we have that vehicle
            if (llGetInventoryType(vehicle) != INVENTORY_OBJECT)
            {
                Debug(["Unknown vehicle", vehicle]);
                llOwnerSay("I do not have an " + vehicle + " - you need a newer rezzer");
                llRemoveInventory(nc_name);
                llResetScript();
            }
            
            // Set the sign texture
            llSetTexture(sign, 5);
            
            // All set, so move on
            state Ready;
            
        }
                
    }
            
}

state Ready
{
    on_rez(integer param)
    {
        // Remove any existing route notecard
        if (nc_name != "") llRemoveInventory(nc_name);
        // Reset the script
        llResetScript();
    }

    changed(integer change)
    {
        // Reset on changed inventory
        if (change & CHANGED_INVENTORY) {
            llResetScript();
        }
    }
    
    state_entry()
    {
        // Set the hovertext and color
        Status("Click me to rez an " + vehicle, "white");
        
        // Create a channel number and listen on it
        ch_comms = channel_base - llFloor(llFrand(channel_range));
        llListen(ch_comms, "", NULL_KEY, "NCREQUEST");
    }
    
    listen(integer channel, string name, key id, string msg)
    {
        Debug(["Heard", name, id, msg]);
        
        // Check the owner matches our owner
        if (llGetOwnerKey(id) == llGetOwner()) {
            
            // Give our notecard to the device
            llGiveInventory(id, nc_name);
            
        }
    }
    
    touch_start(integer detected)
    {
        Debug(["Touched"]);
        
        // Rez our vehicle
        vector pos = llGetPos() + <0.0, 0.0, 5.0>; 
        llRezAtRoot(vehicle, pos, ZERO_VECTOR, ZERO_ROTATION, ch_comms);
    }
    
}
