#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#define PLUGIN_VERSION "8.0"

public Plugin myinfo = {
    name = "HL2DM Dynamic FOV & Weapon Zoom",
    author = "Gemini / Xeogin",
    description = "Reduced Crossbow base FOV to 75 to eliminate remaining glow artifacts.",
    version = PLUGIN_VERSION
};

ConVar g_cvEnabled, g_cvMaxFOV, g_cvSpeedStart, g_cvSpeedCap, g_cvMaxChange, g_cvHideVM;
ConVar g_cvZoomPistol, g_cvZoom357, g_cvZoomRPG;
Handle g_hCookie; 

int g_iCurrentFOV[MAXPLAYERS + 1], g_iPlayerMinFOV[MAXPLAYERS + 1], g_iLastWeaponEnt[MAXPLAYERS + 1];
bool g_bIsZoomed[MAXPLAYERS + 1], g_bKeyBuffer[MAXPLAYERS + 1], g_bNeedsReset[MAXPLAYERS + 1];

public void OnPluginStart() {
    g_cvEnabled = CreateConVar("sm_fov_enabled", "0", "Speed FOV (0=Off, 1=On)"); 
    g_cvHideVM = CreateConVar("sm_fov_zoom_hideviewmodel", "1", "Hide viewmodel when any zoom is active");
    g_cvMaxFOV = CreateConVar("sm_fov_max", "130"); 
    g_cvSpeedStart = CreateConVar("sm_fov_speed_start", "250"); 
    g_cvSpeedCap = CreateConVar("sm_fov_speed_cap", "530"); 
    g_cvMaxChange = CreateConVar("sm_fov_max_change", "1");

    g_cvZoomPistol = CreateConVar("sm_fov_zoom_pistol", "65");
    g_cvZoom357 = CreateConVar("sm_fov_zoom_357", "30");
    g_cvZoomRPG = CreateConVar("sm_fov_zoom_rpg", "50");

    RegConsoleCmd("sm_fov", Command_SetFOV, "Sets your base FOV (90-130)");
    g_hCookie = RegClientCookie("hl2dm_pref_fov_v4", "Stored FOV", CookieAccess_Public);
}

public void OnClientCookiesCached(int client) {
    char sValue[8];
    GetClientCookie(client, g_hCookie, sValue, sizeof(sValue));
    g_iPlayerMinFOV[client] = (sValue[0] != '\0') ? StringToInt(sValue) : 95;
    g_iCurrentFOV[client] = g_iPlayerMinFOV[client];
}

int GetWeaponZoomFOV(const char[] weaponName) {
    if (StrEqual(weaponName, "weapon_pistol"))   return g_cvZoomPistol.IntValue;
    if (StrEqual(weaponName, "weapon_357"))      return g_cvZoom357.IntValue;
    if (StrEqual(weaponName, "weapon_rpg"))      return g_cvZoomRPG.IntValue;
    return 0; 
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return Plugin_Continue;

    int engineFOV = GetEntProp(client, Prop_Send, "m_iFOV");
    float hSpeed = GetHSpeed(client);
    int activeWep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

    char weaponName[32];
    GetClientWeapon(client, weaponName, sizeof(weaponName));

    if (activeWep != g_iLastWeaponEnt[client]) {
        if (g_bIsZoomed[client]) g_bNeedsReset[client] = true;
        g_bIsZoomed[client] = false;
        g_iLastWeaponEnt[client] = activeWep;
    }

    int zoomTarget = GetWeaponZoomFOV(weaponName);

    if (zoomTarget > 0) {
        if (buttons & IN_ATTACK2) {
            if (!g_bKeyBuffer[client]) {
                g_bIsZoomed[client] = !g_bIsZoomed[client];
                if (!g_bIsZoomed[client]) g_bNeedsReset[client] = true;
                g_bKeyBuffer[client] = true;
            }
            buttons &= ~IN_ATTACK2; 
        } else {
            g_bKeyBuffer[client] = false;
        }
    } else {
        if (g_bIsZoomed[client]) g_bNeedsReset[client] = true;
        g_bIsZoomed[client] = false;
    }

    int targetScalingFOV = CalculateScalingFOV(client, hSpeed);
    int pluginTarget = g_bIsZoomed[client] ? zoomTarget : targetScalingFOV;

    // Viewmodel Hiding
    bool engineZoomActive = (engineFOV > 0 && engineFOV < targetScalingFOV);
    if (g_cvHideVM.BoolValue && (g_bIsZoomed[client] || engineZoomActive)) {
        SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 0);
    } else {
        SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);
    }

    // Crossbow Glow Fix: Lock default FOV to 75 while scoped
    if (StrEqual(weaponName, "weapon_crossbow") && engineFOV == 20) {
        SetEntProp(client, Prop_Send, "m_iDefaultFOV", 75);
        return Plugin_Continue; 
    }

    if (!g_bNeedsReset[client] && engineZoomActive) {
        return Plugin_Continue; 
    }

    if (!g_bIsZoomed[client]) {
        g_bNeedsReset[client] = false; 
    }

    SetEntProp(client, Prop_Send, "m_iFOV", pluginTarget);
    SetEntProp(client, Prop_Send, "m_iDefaultFOV", targetScalingFOV);

    return Plugin_Continue;
}

int CalculateScalingFOV(int client, float speed) {
    int base = g_iPlayerMinFOV[client];
    if (!g_cvEnabled.BoolValue) return base;

    float start = g_cvSpeedStart.FloatValue, cap = g_cvSpeedCap.FloatValue;
    int target = base;
    if (speed > start) {
        float ratio = (speed - start) / (cap - start);
        if (ratio > 1.0) ratio = 1.0;
        target += RoundToZero(ratio * (g_cvMaxFOV.IntValue - base));
    }

    int diff = target - g_iCurrentFOV[client];
    if (diff != 0) {
        int move = (diff > 0) ? g_cvMaxChange.IntValue : -g_cvMaxChange.IntValue;
        if (Abs(move) > Abs(diff)) move = diff;
        g_iCurrentFOV[client] += move;
    }
    return g_iCurrentFOV[client];
}

float GetHSpeed(int client) {
    float v[3]; GetEntPropVector(client, Prop_Data, "m_vecVelocity", v);
    return SquareRoot(v[0]*v[0] + v[1]*v[1]);
}

int Abs(int val) { return (val < 0) ? -val : val; }

public Action Command_SetFOV(int client, int args) {
    if (client == 0) return Plugin_Handled;
    if (args < 1) {
        ReplyToCommand(client, "[SM] Usage: !fov <90-130>");
        return Plugin_Handled;
    }
    char arg[16]; GetCmdArg(1, arg, sizeof(arg));
    int value = StringToInt(arg);
    if (value >= 90 && value <= 130) {
        g_iPlayerMinFOV[client] = value;
        g_iCurrentFOV[client] = value; 
        char sValue[8]; IntToString(value, sValue, sizeof(sValue));
        SetClientCookie(client, g_hCookie, sValue);
        ReplyToCommand(client, "[SM] Your base FOV has been set to %d.", value);
    } else {
        ReplyToCommand(client, "[SM] Invalid value. Please choose between 90 and 130.");
    }
    return Plugin_Handled;
}