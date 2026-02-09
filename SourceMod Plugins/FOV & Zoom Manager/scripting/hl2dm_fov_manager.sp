#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#define PLUGIN_VERSION "1.0"

public Plugin myinfo = {
    name = "HL2DM FOV & Zoom Manager",
    author = "Gemini / Xeogin",
    description = "Manages player base FOV via cookies and provides custom per-weapon zoom levels",
    version = PLUGIN_VERSION
};

ConVar g_cvMinFOV, g_cvMaxFOV, g_cvDefaultFOV;
ConVar g_cvHideVM, g_cvZoomPistol, g_cvZoom357, g_cvZoomRPG;
Handle g_hCookie; 

int g_iPlayerBaseFOV[MAXPLAYERS + 1], g_iLastWeaponEnt[MAXPLAYERS + 1];
bool g_bIsZoomed[MAXPLAYERS + 1], g_bKeyBuffer[MAXPLAYERS + 1], g_bNeedsReset[MAXPLAYERS + 1];

public void OnPluginStart() {
    // FOV Range and Defaults
    g_cvMinFOV = CreateConVar("sm_fov_min", "90", "Minimum FOV a player can set.");
    g_cvMaxFOV = CreateConVar("sm_fov_max", "130", "Maximum FOV a player can set.");
    g_cvDefaultFOV = CreateConVar("sm_fov_default", "95", "Default FOV for new players.");

    // Zoom and Viewmodel settings
    g_cvHideVM = CreateConVar("sm_fov_zoom_hideviewmodel", "1", "Hide viewmodel when any zoom is active");
    g_cvZoomPistol = CreateConVar("sm_fov_zoom_pistol", "65", "Zoom FOV for Pistol");
    g_cvZoom357 = CreateConVar("sm_fov_zoom_357", "30", "Zoom FOV for .357 Magnum");
    g_cvZoomRPG = CreateConVar("sm_fov_zoom_rpg", "50", "Zoom FOV for RPG");

    RegConsoleCmd("sm_fov", Command_SetFOV, "Sets your base FOV");
    g_hCookie = RegClientCookie("hl2dm_player_fov_base", "Persistent base FOV preference", CookieAccess_Public);
}

public void OnClientCookiesCached(int client) {
    char sValue[8];
    GetClientCookie(client, g_hCookie, sValue, sizeof(sValue));
    // Use the new Default FOV CVar if no cookie is found
    g_iPlayerBaseFOV[client] = (sValue[0] != '\0') ? StringToInt(sValue) : g_cvDefaultFOV.IntValue;
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
    int activeWep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    char weaponName[32]; GetClientWeapon(client, weaponName, sizeof(weaponName));

    if (activeWep != g_iLastWeaponEnt[client]) {
        if (g_bIsZoomed[client]) g_bNeedsReset[client] = true;
        g_bIsZoomed[client] = false;
        g_iLastWeaponEnt[client] = activeWep;
    }

    int zoomTarget = GetWeaponZoomFOV(weaponName);
    int baseFOV = g_iPlayerBaseFOV[client];

    // 1. Zoom Logic
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

    // 2. Viewmodel Hiding
    bool engineZoomActive = (engineFOV > 0 && engineFOV < baseFOV);
    if (g_cvHideVM.BoolValue && (g_bIsZoomed[client] || engineZoomActive)) {
        SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 0);
    } else {
        SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);
    }

    // 3. Crossbow Glow Fix
    if (StrEqual(weaponName, "weapon_crossbow") && engineFOV == 20) {
        SetEntProp(client, Prop_Send, "m_iDefaultFOV", 75);
        return Plugin_Continue; 
    }

    // 4. Set FOV
    if (!g_bNeedsReset[client] && engineZoomActive) return Plugin_Continue;

    int finalTarget = g_bIsZoomed[client] ? zoomTarget : baseFOV;
    SetEntProp(client, Prop_Send, "m_iFOV", finalTarget);
    SetEntProp(client, Prop_Send, "m_iDefaultFOV", baseFOV);
    g_bNeedsReset[client] = false;

    return Plugin_Continue;
}

public Action Command_SetFOV(int client, int args) {
    if (client == 0) return Plugin_Handled;
    
    if (args < 1) {
        ReplyToCommand(client, "[SM] Usage: !fov <%d-%d>", g_cvMinFOV.IntValue, g_cvMaxFOV.IntValue);
        return Plugin_Handled;
    }

    char arg[16]; GetCmdArg(1, arg, sizeof(arg));
    int value = StringToInt(arg);
    int min = g_cvMinFOV.IntValue;
    int max = g_cvMaxFOV.IntValue;

    if (value >= min && value <= max) {
        g_iPlayerBaseFOV[client] = value;
        char sValue[8]; IntToString(value, sValue, sizeof(sValue));
        SetClientCookie(client, g_hCookie, sValue);
        ReplyToCommand(client, "[SM] Your FOV has been set to %d.", value);
    } else {
        ReplyToCommand(client, "[SM] Invalid value. Please choose between %d and %d.", min, max);
    }
    return Plugin_Handled;
}