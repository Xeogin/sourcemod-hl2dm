#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

enum struct _gConVar
{
    ConVar g_cTimeleftX;
    ConVar g_cTimeleftY;
    ConVar g_cTimeleftR;
    ConVar g_cTimeleftG;
    ConVar g_cTimeleftB;
    ConVar g_cTimeleftI;
}
_gConVar gConVar;

static const char
    PL_NAME[]        = "Timeleft HUD",
    PL_AUTHOR[]      = "Peter Brev, Grey83, Xeogin",
    PL_DESCRIPTION[] = "Provides timeleft on the HUD",
    PL_VERSION[]     = "1.1.2";

Handle hHUD;

public Plugin myinfo =
{
    name        = PL_NAME,
    author      = PL_AUTHOR,
    description = PL_DESCRIPTION,
    version     = PL_VERSION
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if(GetEngineVersion() != Engine_HL2DM)
    {
        FormatEx(error, err_max, "[HL2MP] This plugin is intended for Half-Life 2: Deathmatch only.");
        return APLRes_Failure;
    }
    return APLRes_Success;
}

public void OnPluginStart()
{
    gConVar.g_cTimeleftX = CreateConVar("sm_timeleft_x", "-1.0", "Position the HUD's timeleft on the X axis");
    gConVar.g_cTimeleftY = CreateConVar("sm_timeleft_y", "0.01", "Position the HUD's timeleft on the y axis");
    gConVar.g_cTimeleftR = CreateConVar("sm_timeleft_r", "255", "Red color intensity of the HUD's timeleft", 0, true, 0.0, true, 255.0);
    gConVar.g_cTimeleftG = CreateConVar("sm_timeleft_g", "220", "Green color intensity of the HUD's timeleft", 0, true, 0.0, true, 255.0);
    gConVar.g_cTimeleftB = CreateConVar("sm_timeleft_b", "0", "Blue color intensity of the HUD's timeleft", 0, true, 0.0, true, 255.0);
    gConVar.g_cTimeleftI = CreateConVar("sm_timeleft_i", "255", "Amount of transparency of the HUD's timeleft", 0, true, 0.0, true, 255.0);

    hHUD = CreateHudSynchronizer();
    AutoExecConfig();
}

public void OnMapStart()
{
    CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Countdown(Handle timer)
{
    int time;
    // GetMapTimeLeft returns false if no time limit is set, 
    // or time will be 0 if the limit is explicitly disabled.
    if (!GetMapTimeLeft(time) || time <= 0)
    {
        return Plugin_Continue;
    }

    char left[32];
    if (time > 3599)
    {
        FormatEx(left, sizeof(left), "%ih %02im", time / 3600, (time / 60) % 60);
    }
    else if (time > 59)
    {
        FormatEx(left, sizeof(left), "%d:%02d", time / 60, time % 60);
    }
    else 
    {
        FormatEx(left, sizeof(left), "0:%02d", time);
    }

    SetHudTextParams(
        gConVar.g_cTimeleftX.FloatValue, 
        gConVar.g_cTimeleftY.FloatValue, 
        1.1, 
        gConVar.g_cTimeleftR.IntValue, 
        gConVar.g_cTimeleftG.IntValue, 
        gConVar.g_cTimeleftB.IntValue, 
        gConVar.g_cTimeleftI.IntValue, 
        0, 0.0, 0.0, 0.0
    );

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            ShowSyncHudText(i, hHUD, left);
        }
    }

    return Plugin_Continue;
}