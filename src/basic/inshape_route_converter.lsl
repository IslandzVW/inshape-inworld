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

integer active;
string card;
integer line;
list coords;
list converted;
vector corner;

default
{
    on_rez(integer param)
    {
        llResetScript();
    }

    state_entry()
    {
        while(llGetInventoryNumber(INVENTORY_NOTECARD) > 0) {
            llRemoveInventory(llGetInventoryName(INVENTORY_NOTECARD, 0));
        }
        llSetText("Drop a route notecard in me to covert to global coords\nmake sure you do this in the actual region!", <1.0, 1.0, 1.0>, 1.0);
        active = TRUE;
        corner = llGetRegionCorner();
    }
    
    changed(integer change)
    {
        if ((change & CHANGED_INVENTORY) && (llGetInventoryNumber(INVENTORY_NOTECARD) == 1)) {
            state process;
        }
    }
}

state process
{
    on_rez(integer param)
    {
        llResetScript();
    }

    state_entry()
    {
        active = FALSE;
        card = llGetInventoryName(INVENTORY_NOTECARD, 0);
        llSetText("Processing " + card, <1.0, 0.5, 0.0>, 1.0);
        llOwnerSay("Reading notecard ...");
        line = 0;
        coords = [];
        converted = [];
        llGetNotecardLine(card, line);
    }
    
    dataserver(key query, string data)
    {
        if (data == EOF) {
            llOwnerSay("Convertng coordinates ...");
            integer i;
            integer n = llGetListLength(coords);
            vector pos;
            vector newpos;
            list newparts;
            for (i=0; i<n; i++) {
                pos = llList2Vector(coords, i);
                if (pos == ZERO_VECTOR) {
                    llOwnerSay("ERROR : Coordinate " + (string)i + " on line " + (string)line + " is invalid!");
                } else
                if (pos.x > 256.0) {
                    llOwnerSay("ERROR : Coordinate " + (string)i + " on line " + (string)line + " is already global! Aborting ...");
                    state default;
                } else {
                    newpos = pos + corner;
                    newparts += [newpos];
                    if (llGetListLength(newparts) > 4) {
                        converted += [llDumpList2String(newparts, "|")];
                        newparts = [];
                    }
                }
            }
            if (llGetListLength(newparts) > 0) {
                converted += [llDumpList2String(newparts, "|")];
            }
            llOwnerSay("Saving notecard ...");
            iwMakeNotecard(card + " GLOBAL", converted);
            llOwnerSay("Sending");
            llGiveInventory(llGetOwner(), card + " GLOBAL");
            state default;
        } else {
            coords += llParseStringKeepNulls(data, ["|"], []);
            line ++;
            llGetNotecardLine(card, line);
        }
    }
    
}