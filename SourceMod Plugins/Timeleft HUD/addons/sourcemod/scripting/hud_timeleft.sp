#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

enum struct _gConVar
{
    ConVar g_cTimeleftPos;
    ConVar g_cTimeleftColor;
    ConVar g_cTimeleftWarnColor;
}
_gConVar gConVar;

static const char
    PL_NAME[]        = "Timeleft HUD",
    PL_AUTHOR[]      = "Peter Brev, Grey83, Gemini+Xeogin",
    PL_DESCRIPTION[] = "Displays the remaining timeleft on every player's HUD",
    PL_VERSION[]     = "1.1.3";

Handle hHUD;

// Global optimized cache variables
char  g_sCachedText[32];
int   g_iLastParsedTime = -1;

float g_fPosCodeX = -1.0;
float g_fPosCodeY = 0.01;

int   g_iColorNormal[3] = {255, 220, 0};
int   g_iColorWarn[3]   = {255, 0, 0};

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
    gConVar.g_cTimeleftPos       = CreateConVar("sm_timeleft_pos", "-1.0,0.01", "HUD screen position coordinates: <X axis>,<Y axis>");
    gConVar.g_cTimeleftColor     = CreateConVar("sm_timeleft_color", "255,220,0", "Default color of the timer: <Red>,<Green>,<Blue>");
    gConVar.g_cTimeleftWarnColor = CreateConVar("sm_timeleft_warn_color", "255,0,0", "Warning color under 60 seconds: <Red>,<Green>,<Blue>");

    gConVar.g_cTimeleftPos.AddChangeHook(OnCvarChanged_Position);
    gConVar.g_cTimeleftColor.AddChangeHook(OnCvarChanged_Colors);
    gConVar.g_cTimeleftWarnColor.AddChangeHook(OnCvarChanged_Colors);

    hHUD = CreateHudSynchronizer();
    AutoExecConfig(true, "timeleft_hud");
}

public void OnMapStart()
{
    g_iLastParsedTime = -1; 
    
    CachePosition();
    CacheColors();

    CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnCvarChanged_Position(ConVar convar, const char[] oldValue, const char[] newValue)
{
    CachePosition();
}

public void OnCvarChanged_Colors(ConVar convar, const char[] oldValue, const char[] newValue)
{
    CacheColors();
}

void CachePosition()
{
    char sPos[32];
    gConVar.g_cTimeleftPos.GetString(sPos, sizeof(sPos));
    
    char sCoord[2][16];
    if (ExplodeString(sPos, ",", sCoord, sizeof(sCoord), sizeof(sCoord[])) >= 2)
    {
        TrimString(sCoord[0]);
        TrimString(sCoord[1]);
        g_fPosCodeX = StringToFloat(sCoord[0]);
        g_fPosCodeY = StringToFloat(sCoord[1]);
    }
}

void CacheColors()
{
    char sRGBColor[32], sValues[3][16];
    
    gConVar.g_cTimeleftColor.GetString(sRGBColor, sizeof(sRGBColor));
    if (ExplodeString(sRGBColor, ",", sValues, sizeof(sValues), sizeof(sValues[])) >= 3)
    {
        g_iColorNormal[0] = StringToInt(sValues[0]);
        g_iColorNormal[1] = StringToInt(sValues[1]);
        g_iColorNormal[2] = StringToInt(sValues[2]);
    }

    gConVar.g_cTimeleftWarnColor.GetString(sRGBColor, sizeof(sRGBColor));
    if (ExplodeString(sRGBColor, ",", sValues, sizeof(sValues), sizeof(sValues[])) >= 3)
    {
        g_iColorWarn[0] = StringToInt(sValues[0]);
        g_iColorWarn[1] = StringToInt(sValues[1]);
        g_iColorWarn[2] = StringToInt(sValues[2]);
    }
}

public Action Timer_Countdown(Handle timer)
{
    int time;
    if (!GetMapTimeLeft(time) || time <= 0)
    {
        return Plugin_Continue;
    }

    if (time != g_iLastParsedTime)
    {
        g_iLastParsedTime = time;

        if (time > 3599)
        {
            FormatEx(g_sCachedText, sizeof(g_sCachedText), "%ih %02im", time / 3600, (time / 60) % 60);
        }
        else if (time > 59)
        {
            FormatEx(g_sCachedText, sizeof(g_sCachedText), "%d:%02d", time / 60, time % 60);
        }
        else 
        {
            FormatEx(g_sCachedText, sizeof(g_sCachedText), "%d", time);
        }
    }

    float currentY = g_fPosCodeY;
    int r = g_iColorNormal[0];
    int g = g_iColorNormal[1];
    int b = g_iColorNormal[2];

    if (time <= 59)
    {
        r = g_iColorWarn[0];
        g = g_iColorWarn[1];
        b = g_iColorWarn[2];

        if (time <= 9)
        {
            float targetCenter = 0.45;
            if (g_fPosCodeY < targetCenter)
            {
                float totalDistance = targetCenter - g_fPosCodeY;
                // Shifted window calculation so 9 takes a visible downward step immediately
                float stepMultiplier = (10.0 - float(time)) / 9.0; 
                currentY = g_fPosCodeY + (totalDistance * stepMultiplier);
            }
        }
    }

    SetHudTextParams(g_fPosCodeX, currentY, 1.05, r, g, b, 255);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            ShowSyncHudText(i, hHUD, g_sCachedText);
        }
    }

    return Plugin_Continue;
}