#include <sourcemod>
#include <sdktools>

public Plugin myinfo = {
    name = "NextBot Linux Fix",
    author = "Gemini",
    description = "Manages NextBot identity, score persistence, and automated navigation mesh generation.",
    version = "8.7.0"
};

char g_BotNames[MAXPLAYERS + 1][32];
int g_BotKills[MAXPLAYERS + 1];
int g_BotDeaths[MAXPLAYERS + 1];

char g_IdentityNames[][] = { "Bot Cop", "ReBot" };
char g_IdentityModels[][] = { "models/combine_super_soldier.mdl", "models/humans/group03/male_07.mdl" };

public void OnPluginStart() {
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    HookEvent("player_connect", Event_Silence, EventHookMode_Pre);
    HookEvent("player_disconnect", Event_Silence, EventHookMode_Pre);
    HookEvent("player_team", Event_Silence, EventHookMode_Pre);
}

public void OnMapStart() {
    // Force reset the bot quota to prevent the 'random value' bug from previous nav-gen sessions
    ServerCommand("hl2mp_bot_quota 0");

    for (int i = 0; i <= MAXPLAYERS; i++) {
        g_BotNames[i][0] = '\0';
        g_BotKills[i] = 0;
        g_BotDeaths[i] = 0;
    }

    PrecacheModel(g_IdentityModels[0], true);
    PrecacheModel(g_IdentityModels[1], true);

    char mapName[64];
    GetCurrentMap(mapName, sizeof(mapName));
    char navPath[128];
    Format(navPath, sizeof(navPath), "maps/%s.nav", mapName);

    if (!FileExists(navPath)) {
        CreateTimer(3.0, Timer_BeginNavGen);
    }
}

public Action Timer_BeginNavGen(Handle timer) {
    PrintToChatAll("\x04[SM] \x01Navigation mesh not found. \x03Optimizing this map for bots...");
    PrintToChatAll("\x04[SM] \x01The game will freeze for a moment and the \x02map will change\x01 when done.");
    CreateTimer(2.0, Timer_ExecuteNavGen);
    return Plugin_Stop;
}

public Action Timer_ExecuteNavGen(Handle timer) {
    int flags = GetCommandFlags("nav_generate");
    if (flags != -1) {
        SetCommandFlags("nav_generate", flags & ~FCVAR_CHEAT & ~FCVAR_SPONLY & ~FCVAR_REPLICATED);
        InsertServerCommand("nav_generate");
        ServerExecute();
        SetCommandFlags("nav_generate", flags);
    }
    return Plugin_Stop;
}

public Action Event_Silence(Event event, const char[] name, bool dontBroadcast) {
    event.BroadcastDisabled = true; 
    return Plugin_Handled; 
}

public void OnClientPutInServer(int client) {
    if (!IsFakeClient(client)) {
        CreateTimer(2.0, Timer_CheckBotBalance);
    } else {
        CreateTimer(0.1, Timer_RestoreScore, GetClientUserId(client));
    }
}

public void OnClientDisconnect_Post(int client) {
    CreateTimer(2.0, Timer_CheckBotBalance);
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsFakeClient(client)) {
        GetClientName(client, g_BotNames[client], 32);
        g_BotKills[client] = GetClientFrags(client);
        CreateTimer(0.5, Timer_KickBot, GetClientUserId(client));
    }
    return Plugin_Continue;
}

public Action Timer_KickBot(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client)) {
        g_BotDeaths[client] = GetClientDeaths(client);
        ServerCommand("kickid %d \"Stability\"", userid);
    }
    return Plugin_Stop;
}

public Action Timer_CheckBotBalance(Handle timer) {
    int humanCount = 0;
    int botCount = 0;

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
            if (IsFakeClient(i)) botCount++;
            else humanCount++;
        }
    }

    if (humanCount == 1) {
        // Ensure the quota hasn't been set to a weird number by the engine
        ServerCommand("hl2mp_bot_quota 0");
        
        if (botCount < 2) {
            int toAdd = 2 - botCount;
            for (int i = 0; i < toAdd; i++) ServerCommand("hl2mp_bot_add");
        } else if (botCount > 2) {
            ServerCommand("hl2mp_bot_kick"); 
        }
    } else {
        if (botCount > 0) ServerCommand("hl2mp_bot_kick");
    }
    return Plugin_Stop;
}

public Action Timer_RestoreScore(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) return Plugin_Stop;

    int botIdx = -1;
    int currentBotNum = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && IsFakeClient(i)) {
            if (i == client) {
                botIdx = currentBotNum;
                break;
            }
            currentBotNum++;
        }
    }

    if (botIdx >= 0 && botIdx < 2) {
        SetClientName(client, g_IdentityNames[botIdx]);
        SetEntityModel(client, g_IdentityModels[botIdx]);

        for (int i = 1; i <= MaxClients; i++) {
            if (StrEqual(g_BotNames[i], g_IdentityNames[botIdx])) {
                SetEntProp(client, Prop_Data, "m_iFrags", g_BotKills[i]);
                SetEntProp(client, Prop_Data, "m_iDeaths", g_BotDeaths[i]);
                
                int manager = GetPlayerResourceEntity();
                if (manager != -1) {
                    SetEntProp(manager, Prop_Send, "m_iScore", g_BotKills[i], _, client);
                    SetEntProp(manager, Prop_Send, "m_iDeaths", g_BotDeaths[i], _, client);
                }
                break;
            }
        }
    }
    return Plugin_Stop;
}