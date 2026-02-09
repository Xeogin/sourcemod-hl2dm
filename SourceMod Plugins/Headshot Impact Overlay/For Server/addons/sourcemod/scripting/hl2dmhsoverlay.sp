#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.6"

#define CUSTOM_OVERLAY_1 "hsoverlays/bullet1a"
#define CUSTOM_OVERLAY_2 "hsoverlays/bullet2b"

// Stock fallback
#define FALLBACK_OVERLAY "effects/red"

#define SOUND_PATH "physics/glass/glass_impact_bullet1.wav"

ConVar g_hHS_enabled;
ConVar g_hDebug_enabled;
bool g_bCustomFound = false;

int g_bClientPrefHsOverlays[MAXPLAYERS + 1];
int g_LastHitGroup[MAXPLAYERS + 1];
Handle g_hClientCookieHsOverlays = INVALID_HANDLE;

public Plugin myinfo =
{
    name = "[HL2DM] Headshot Impact Overlay",
    author = "TonyBaretta, Gemini+Xeogin",
    description = "Displays overlay to player upon death to a headshot",
    version = PLUGIN_VERSION,
};

public void OnPluginStart() {
    CreateConVar("hl2_hs_impact_version", PLUGIN_VERSION, "Plugin Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    g_hHS_enabled = CreateConVar("sm_hsonly_enabled", "1", "1 = Headshots only, 0 = All deaths");
    g_hDebug_enabled = CreateConVar("sm_hsimpact_debug", "0", "1 = Enable debug mode, 0 = Disabled");
    
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_spawn", Event_PlayerSpawn); 
    
    RegConsoleCmd("sm_hsimpact", Command_HsImpact, "Toggle Headshot overlay preference");
    RegConsoleCmd("sm_testoverlay", Command_TestOverlay, "Triggers the overlay and sound on yourself for testing.");
    
    g_hClientCookieHsOverlays = RegClientCookie("Headshot Impact Overlays", "", CookieAccess_Private);
}

public void OnMapStart() {
    PrecacheSound(SOUND_PATH, true);
    
    char vmtPath[PLATFORM_MAX_PATH];
    Format(vmtPath, sizeof(vmtPath), "materials/%s.vmt", CUSTOM_OVERLAY_1);
    
    if (FileExists(vmtPath)) {
        g_bCustomFound = true;
        PrintToServer("[HS Impact] Custom overlays found. Preparing downloads.");
        PrepareDownloads(CUSTOM_OVERLAY_1);
        PrepareDownloads(CUSTOM_OVERLAY_2);
    } else {
        g_bCustomFound = false;
        PrintToServer("[HS Impact] Custom overlays NOT found. Using fallback: %s", FALLBACK_OVERLAY);
    }
}

void PrepareDownloads(const char[] path) {
    char buffer[PLATFORM_MAX_PATH];
    Format(buffer, sizeof(buffer), "materials/%s.vmt", path);
    if (FileExists(buffer)) AddFileToDownloadsTable(buffer);
    
    Format(buffer, sizeof(buffer), "materials/%s.vtf", path);
    if (FileExists(buffer)) AddFileToDownloadsTable(buffer);
}

public void OnClientPutInServer(int client) {
    g_bClientPrefHsOverlays[client] = 1; 
    if (AreClientCookiesCached(client)) LoadCookies(client);
    SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup) {
    if (victim > 0 && victim <= MAXPLAYERS) {
        g_LastHitGroup[victim] = hitgroup;
    }
    return Plugin_Continue;
}

void LoadCookies(int client) {
    char buffer[5];
    GetClientCookie(client, g_hClientCookieHsOverlays, buffer, sizeof(buffer));
    if (buffer[0] != '\0') g_bClientPrefHsOverlays[client] = StringToInt(buffer);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client || !IsClientInGame(client)) return;

    bool isHeadshot = (g_LastHitGroup[client] == 1);
    bool prefEnabled = (g_bClientPrefHsOverlays[client] == 1);
    bool forceHS = g_hHS_enabled.BoolValue;

    if (prefEnabled && (!forceHS || isHeadshot)) {
        char sOverlay[PLATFORM_MAX_PATH];
        
        if (g_bCustomFound) {
            // Randomly pick 1 or 2
            strcopy(sOverlay, sizeof(sOverlay), (GetRandomInt(1, 2) == 1) ? CUSTOM_OVERLAY_1 : CUSTOM_OVERLAY_2);
        } else {
            strcopy(sOverlay, sizeof(sOverlay), FALLBACK_OVERLAY);
        }

        if (g_hDebug_enabled.BoolValue) {
            PrintToChat(client, "\x04[HS] \x01Impact! Overlay: %s", sOverlay);
        }
        
        SetClientOverlay(client, sOverlay);
        EmitSoundToClient(client, SOUND_PATH);
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && IsClientInGame(client)) {
        g_LastHitGroup[client] = 0;
        SetClientOverlay(client, ""); 
    }
}

public Action Command_TestOverlay(int client, int args) {
    if (!client || !IsClientInGame(client)) return Plugin_Handled;

    if (!g_hDebug_enabled.BoolValue) {
        ReplyToCommand(client, "[SM] Debug mode is disabled.");
        return Plugin_Handled;
    }

    char sOverlay[PLATFORM_MAX_PATH];
    strcopy(sOverlay, sizeof(sOverlay), g_bCustomFound ? CUSTOM_OVERLAY_1 : FALLBACK_OVERLAY);

    PrintToChat(client, "\x04[Debug] \x01Testing: %s", sOverlay);
    SetClientOverlay(client, sOverlay);
    EmitSoundToClient(client, SOUND_PATH);
    
    CreateTimer(3.0, Timer_ClearTest, GetClientUserId(client));
    return Plugin_Handled;
}

public Action Timer_ClearTest(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client && IsClientInGame(client)) SetClientOverlay(client, "");
    return Plugin_Stop;
}

void SetClientOverlay(int client, const char[] strOverlay) {
    if (!client || !IsClientInGame(client)) return;

    int iFlags = GetCommandFlags("r_screenoverlay") & (~FCVAR_CHEAT);
    SetCommandFlags("r_screenoverlay", iFlags);
    
    ClientCommand(client, "r_screenoverlay \"%s\"", strOverlay);
    
    DataPack pack;
    CreateDataTimer(0.1, Timer_ReapplyOverlay, pack);
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(strOverlay);

    SetCommandFlags("r_screenoverlay", iFlags | FCVAR_CHEAT);
}

public Action Timer_ReapplyOverlay(Handle timer, DataPack pack) {
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char strOverlay[PLATFORM_MAX_PATH];
    pack.ReadString(strOverlay, sizeof(strOverlay));

    if (client && IsClientInGame(client)) {
        int iFlags = GetCommandFlags("r_screenoverlay") & (~FCVAR_CHEAT);
        SetCommandFlags("r_screenoverlay", iFlags);
        ClientCommand(client, "r_screenoverlay \"%s\"", strOverlay);
        SetCommandFlags("r_screenoverlay", iFlags | FCVAR_CHEAT);
    }
    return Plugin_Stop;
}

public Action Command_HsImpact(int client, int args) {
    if (!client) return Plugin_Handled;
    g_bClientPrefHsOverlays[client] = !g_bClientPrefHsOverlays[client];
    
    char buffer[5];
    IntToString(g_bClientPrefHsOverlays[client], buffer, sizeof(buffer));
    SetClientCookie(client, g_hClientCookieHsOverlays, buffer);
    
    PrintToChat(client, "Hs Impact %s", g_bClientPrefHsOverlays[client] ? "Enabled" : "Disabled");
    return Plugin_Handled;
}