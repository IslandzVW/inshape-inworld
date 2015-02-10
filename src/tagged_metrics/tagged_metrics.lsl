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
// Demonstrates how to access InShape tagged metrics such as heartrate
// Put this script in an object and wear it as a HUD
//----------------------------------------------------------------------------

integer COMMAND_CHANNEL = -129;
string HEARTRATE_METRIC_NAME = "hr";
integer handle;

list DecodeParams(string params) 
{
    return llParseString2List(params, ["|"], []);
}

float FindMetricFloatVal(list params, string metricTag)
{
    integer length = llGetListLength(params);
    
    integer index;// default is 0
    while (index < length)
    {
        string val = llList2String(params, index);
        
        //split by :
        list nameValPair = llParseString2List(val, [":"], []);
        if (llGetListLength(nameValPair) == 2)
        {
            if (llList2String(nameValPair, 0) == metricTag)
            {
                return llList2Float(nameValPair, 1);
            }
        }
        
        ++index;
    }
    
    return 0.0;
}

default
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    state_entry()
    {
        handle = llListen(COMMAND_CHANNEL, "", llGetOwner(), "");
    }
    
    listen( integer channel, string name, key id, string message )
    {
        // If we hear anything then check it is the rider we are hearing
        // or something owned by them if we are in simulation mode
        if (llGetOwner() == id)
        {
            //this is our owner talking on our command channel.
            //lets decode and make the appropriate changes
            list params = DecodeParams(message);
            
            //params is EXERCISE_TYPE|AVG_MAG|PULSES_PER_SECOND[|tagged metric...]
            integer exerciseType = llList2Integer(params, 0);
            float avgMag = llList2Float(params, 1);
            float pps = llList2Float(params, 2);
            
            //get the tagged metric for heartrate
            float hr = FindMetricFloatVal(params, HEARTRATE_METRIC_NAME);
            
            string hrstr;
            if (hr == 0.0) hrstr = "N/A";
            else hrstr = (string)hr;
            
            llSetText(  "Power: " + (string)avgMag + "\n" +
                        "Steps/Cycles: " + (string) pps + "\n" +
                        "HeartRate: " + hrstr,
                        <1.0, 1.0, 1.0>, 1.0);
        }
    }
}