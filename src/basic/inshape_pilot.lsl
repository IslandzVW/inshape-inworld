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
// Route Runner Pilot Script
//
// v2.5 Split the script into two. This is the "pilot" that calculates speed
//      from the external inputs, and animates the avatar. The other is the 
//      "engine" that does the actual movement based on average speed.
//
//      Listener is now agent-specific (unless in simulation)
//      Animation is now driven by commands from engine script
//      Also added SIMULATE mode that accept input from a HUD
//
//----------------------------------------------------------------------------

integer DEBUG = FALSE;
integer SIMULATE = TRUE;

integer COMMAND_CHANNEL = -129;

integer EXERCISE_TYPE_WALKING = 1;
integer EXERCISE_TYPE_RUNNING = 2;
integer EXERCISE_TYPE_BIKE = 3;
integer EXERCISE_TYPE_ROWING = 4;
integer EXERCISE_TYPE_STEPPER = 5;

//how much weight we give the stride rate in determining final speed
float STRIDE_WEIGHT = 0.5;
//how much weight we give the avg power in determining the final speed
float POWER_WEIGHT = 0.5;

integer NUM_SPEEDS = 5;

float IDLE_SECONDS_BEFORE_STOPPING = 5.0;
float INTERVAL = 1.0;

 
//stride rates for running or walking
list strideRates = [1.0, 1.5, 2.0, 2.5, 3.0];

//cadence rates for bikes or ellipticals
list cadenceRates = [0.5, 0.75, 1.0, 1.5, 2.0];

//cadence rates for rowers
list rowingCadenceRates = [0.25, 0.5, 0.75, 1.0, 1.5];


//power percentiles for walking
list walkingPowerPercentiles = [2.6, 5.3, 10.6, 21.2, 42.4];

//power percentiles for running
list runningPowerPercentiles = [10.0, 21.0, 42.0, 55.0, 70.0];

//power percentiles for biking
list bikingPowerPercentiles = [1.0, 1.5, 2.4, 4.3, 9.8];

//power percentiles for rowing (phone in pocket)
list rowingPowerPercentiles = [0.2, 0.6, 1.0, 1.4, 3.8];


float lastMessageTime;

integer link;

key rider;
integer handle;

integer speed;
integer type;
integer anim;

list anims = ["stand_1", "Walking0", "Run suteki"];

ProcessInput(integer exerciseType, float avgMag, float pps)
{
    if (pps == 0.0)
    {
        SetSpeed(0, 0);
        return;
    }
    
    list powerPercentiles;
    list rates;
    
    if (exerciseType == EXERCISE_TYPE_WALKING) 
    {
        powerPercentiles = walkingPowerPercentiles;
        rates = strideRates;
    }
    else if (exerciseType == EXERCISE_TYPE_RUNNING)
    {
        powerPercentiles = runningPowerPercentiles;
        rates = strideRates;
    }
    else if (exerciseType == EXERCISE_TYPE_BIKE)
    {
        powerPercentiles = bikingPowerPercentiles;
        rates = cadenceRates;
    }
    else if (exerciseType == EXERCISE_TYPE_ROWING)
    {
        powerPercentiles = rowingPowerPercentiles;
        rates = rowingCadenceRates;
    }
    
    integer i;
    
    //find the nearest match at or below the current stride rate
    integer strideRateIndex = 0;
    for (i=0; i < NUM_SPEEDS; i++)
    {
        float indexRate = llList2Float(rates, i);
        if (pps == indexRate) 
        {
            strideRateIndex = i;
            jump gotRate;
        }
        else if (pps <  indexRate)
        {
            strideRateIndex = i - 1;
            jump gotRate;
        }
    }

    if (i == NUM_SPEEDS) strideRateIndex = NUM_SPEEDS - 1; //we got to the end, they are off the chart
    
@gotRate;
    
    //find the nearest match at or below the current power
    integer powerIndex = 0;
    for (i=0; i < NUM_SPEEDS; i++)
    {
        float indexPower = llList2Float(powerPercentiles, i);
        if (avgMag == indexPower) 
        {
            powerIndex = i;
            jump gotPower;
        }
        else if (avgMag < indexPower)
        {
            powerIndex = i - 1;
            jump gotPower;
        }
    }

    if (i == NUM_SPEEDS) powerIndex = NUM_SPEEDS - 1; //we got to the end, they are off the chart
    
@gotPower;

    //test for powers and stride rates below the minimum but above 0
    if (powerIndex == -1) powerIndex = 0;
    if (strideRateIndex == -1) strideRateIndex = 0;
    
    //calculate the resulting speed
    integer calcSpeed = llRound((powerIndex * POWER_WEIGHT) + (strideRateIndex * STRIDE_WEIGHT));
    
    //final sanity checks in case of rounding errors
    if (calcSpeed < 0) calcSpeed = 0;
    if (calcSpeed >= NUM_SPEEDS) calcSpeed = NUM_SPEEDS - 1;
    
    //set the new speed (0 to 4)
    SetSpeed(calcSpeed, exerciseType);

}

SetSpeed(integer pSpeed, integer pType)
{
    // If speed has changed then act accordingly
    if ((pSpeed != speed) || (pType != type))
    {
        // Have we just stopped moving?
        if (pSpeed == 0)
        {
            // Stop the timer
            llSetTimerEvent(0);
            if (DEBUG) llOwnerSay("Stopping timer");
        } else
        
        // Have we just started moving?
        if (speed == 0)
        {
            llSetTimerEvent(INTERVAL);
            if (DEBUG) llOwnerSay("Starting timer");
        }
        
        // Send the data to the engine script
        llMessageLinked(LINK_ROOT, pType * NUM_SPEEDS + pSpeed, "input", rider);
        
        // Save it
        speed = pSpeed;
        type = pType;
    }
}

SetCamera()
{

    if (llGetPermissions() & PERMISSION_CONTROL_CAMERA)
    {
        llSetCameraParams( [CAMERA_ACTIVE, TRUE, 
                            CAMERA_FOCUS_LOCKED, FALSE,
                            CAMERA_FOCUS_THRESHOLD, 0.3,
                            CAMERA_FOCUS_OFFSET, <0.0, 0.0, 0.5>,
                            CAMERA_PITCH, 5.0,
                            CAMERA_DISTANCE, 4.0,
                            CAMERA_BEHINDNESS_ANGLE, 0.2,
                            CAMERA_BEHINDNESS_LAG, 0.5,
                            CAMERA_POSITION_THRESHOLD, 0.2,
                            CAMERA_POSITION_LAG, 0.2]);
    }
}

SetAnim(integer pAnim)
{
    // If we have an avatar then change their animation if we need to
    if ((rider != NULL_KEY) && (pAnim != anim))
    {
        // If we have an anim then stop the current one
        if (anim >= 0)
        {
            llStopAnimation(llList2String(anims, anim));
            llSleep(0.1); // lets anim change
        }
        // Start the new one
        string animName = llList2String(anims, pAnim);
        llStartAnimation(animName);
        // Save it
        anim = pAnim;
    }
}

HideMe()
{
    llSetText("", <1.0, 1.0, 1.0>, 1.0);
    llSetAlpha(0.0, ALL_SIDES);
}

ShowMe()
{
    llSetText("Right-Click me and select Sit\nto join this team", <1.0, 1.0, 1.0>, 1.0);
    llSetAlpha(1.0, ALL_SIDES);
}

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
        // Unsit anyone already on us when the script starts
        if (llAvatarOnSitTarget() != NULL_KEY)
        {
            llUnSit(llAvatarOnSitTarget());
        }
        llSitTarget(<0.0,0.0,0.1>, ZERO_ROTATION);
        // Get my link number to save time later
        link = llGetLinkNumber();
        // Tell the master script that I am here and ready
        SetSpeed(0,0);
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
            integer exerciseType = llList2Integer(params, 0);
            float avgMag = llList2Float(params, 1);
            float pps = llList2Float(params, 2);
            
            ProcessInput(exerciseType, avgMag, pps);
            
            lastMessageTime = llGetGMTclock();
        }
    }
    
    link_message(integer sender, integer num, string msg, key id)
    {
        // Check for animation
        if (msg == "anim")
        {
            if (rider != NULL_KEY)
            {
                SetAnim(num);
            }
        } else
        
        // Check for visibility
        if (msg == "visible")
        {
            if (num)
            {
                ShowMe();
            } else {
                HideMe();
            }
        } else
        
        // Check for reset
        if (msg == "reset")
        {
            llResetScript();
        }
    }

    changed(integer change)
    {
        // Check for someone getting on or off
        if ((change & CHANGED_LINK) && (llAvatarOnSitTarget() != rider))
        {
            // Remove the listener if we have one
            if (handle)
            {
                llListenRemove(handle);
                handle = 0;
            }
            
            // Check for a rider
            rider = llAvatarOnSitTarget();
            if (rider == NULL_KEY)
            {
                if (DEBUG) llOwnerSay("Rider dismounted - stopping this tracker");
                
                // Reset everything
                llSetTimerEvent(0);
                speed = 0;
                anim = -1;
                
                // Send the dismount instruction
                llMessageLinked(LINK_ROOT, 0, "dismount", NULL_KEY);
            } else {
                if (DEBUG) llOwnerSay("Rider is " + llKey2Name(rider));
                
                // Add a user-specific listener (or a general one for simulation)
                if (SIMULATE)
                {
                    handle = llListen(COMMAND_CHANNEL, "", NULL_KEY, "");
                } else {
                    handle = llListen(COMMAND_CHANNEL, "", rider, "");
                }
                
                // Set the current speed
                speed = 0;
                
                // Send the mount instruction
                llMessageLinked(LINK_ROOT, 0, "mount", rider);
                
                // Request permissions
                llRequestPermissions(rider, PERMISSION_CONTROL_CAMERA | 
                                            PERMISSION_TRIGGER_ANIMATION);
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
            llSleep(0.1); // give anim time to stop
            
            // Set initial animation
            anim = -1; // force an animation
            SetAnim(0);
        }
    }

    timer()
    {
        //are we still getting messages?
        if (llGetGMTclock() - lastMessageTime > IDLE_SECONDS_BEFORE_STOPPING)
        {
            //nope, stop
            SetSpeed(0, 0);
        }
    }
    
}
