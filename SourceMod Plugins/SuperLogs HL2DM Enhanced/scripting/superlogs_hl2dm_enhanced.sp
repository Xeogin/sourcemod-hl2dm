#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "2.6"

#define LOG_SHOTS           0
#define LOG_HITS            1
#define LOG_KILLS           2
#define LOG_HEADSHOTS       3
#define LOG_TK              4
#define LOG_DAMAGE          5
#define LOG_DEATHS          6
#define LOG_HIT_GENERIC     7
#define LOG_HIT_HEAD        8
#define LOG_HIT_CHEST       9
#define LOG_HIT_STOMACH     10
#define LOG_HIT_LEFTARM     11
#define LOG_HIT_RIGHTARM    12
#define LOG_HIT_LEFTLEG     13
#define LOG_HIT_RIGHTLEG    14
#define LOG_SKILL_HITS      15 
#define STATS_COUNT         16

#define WEAPON_COUNT 14
char g_szWeaponList[WEAPON_COUNT][] = { 
    "crossbow_bolt", "smg1", "357", "shotgun", "ar2", "pistol", 
    "frag", "slam", "physcannon", "combine_ball", "crowbar", "rpg",
    "stunstick", "world"
};

int g_iWeaponStats[MAXPLAYERS+1][WEAPON_COUNT][STATS_COUNT];
StringMap g_hWeaponMap;
int g_iNextHitgroup[MAXPLAYERS+1];
int g_iOwnerOffset = -1;
Handle g_hBoltStack = INVALID_HANDLE;

ConVar g_cvar_locations;
ConVar g_cvar_skill_velocity;

public Plugin myinfo = {
    name = "SuperLogs: HL2DM Enhanced",
    author = "Gemini & Xeogin",
    description = "Logging with movement-based skill tracking",
    version = PLUGIN_VERSION,
};

public void OnPluginStart() {
    g_cvar_locations = CreateConVar("superlogs_locations", "1", "Log coordinates on death");
    g_cvar_skill_velocity = CreateConVar("superlogs_skill_velocity", "150.0", "Velocity threshold for skill hits");

    g_iOwnerOffset = FindSendPropInfo("CCrossbowBolt", "m_hOwnerEntity");
    g_hBoltStack = CreateStack();

    g_hWeaponMap = new StringMap();
    for (int i = 0; i < WEAPON_COUNT; i++) {
        g_hWeaponMap.SetValue(g_szWeaponList[i], i);
    }

    HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn);

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) OnClientPutInServer(i);
    }
}

public void OnClientPutInServer(int client) {
    SDKHook(client, SDKHook_FireBulletsPost, OnFireBullets);
    SDKHook(client, SDKHook_TraceAttackPost, OnTraceAttack);
    SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamage);
    ResetPlayerStats(client);
}

public void OnEntityCreated(int entity, const char[] classname) {
    if (StrEqual(classname, "crossbow_bolt")) PushStackCell(g_hBoltStack, entity);
}

public void OnGameFrame() {
    int entity;
    while (!IsStackEmpty(g_hBoltStack)) {
        PopStackCell(g_hBoltStack, entity);
        if (IsValidEntity(entity)) {
            int owner = GetEntDataEnt2(entity, g_iOwnerOffset);
            if (owner > 0 && owner <= MaxClients) g_iWeaponStats[owner][0][LOG_SHOTS]++;
        }
    }
}

public void OnFireBullets(int attacker, int shots, char[] weaponname) {
    if (attacker <= 0 || attacker > MaxClients) return;
    int idx = GetMapWeaponIndex(weaponname);
    if (idx != -1) g_iWeaponStats[attacker][idx][LOG_SHOTS] += shots;
}

public void OnTraceAttack(int victim, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup) {
    if (victim > 0 && victim <= MaxClients) g_iNextHitgroup[victim] = hitgroup;
}

public void OnTakeDamage(int victim, int attacker, int inflictor, float damage, int damagetype) {
    if (attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients) return;
    
    int idx = -1;
    if (IsValidEntity(inflictor)) {
        char cls[64];
        GetEntityNetClass(inflictor, cls, sizeof(cls));
        if (StrEqual(cls, "CCrossbowBolt")) idx = 0;
        else if (StrEqual(cls, "CPropCombineBall")) idx = 9;
        else if (StrEqual(cls, "CWeaponRPG") || StrEqual(cls, "rpg_missile")) idx = 11;
    }

    if (idx == -1) {
        char weapon[32];
        GetClientWeapon(attacker, weapon, sizeof(weapon));
        idx = GetMapWeaponIndex(weapon);
    }
    
    if (idx == -1) idx = (WEAPON_COUNT - 1);

    // Skill Velocity Check
    float vel[3];
    GetEntPropVector(attacker, Prop_Data, "m_vecVelocity", vel);
    if (GetVectorLength(vel) >= g_cvar_skill_velocity.FloatValue) {
        g_iWeaponStats[attacker][idx][LOG_SKILL_HITS]++;
    }

    g_iWeaponStats[attacker][idx][LOG_HITS]++;
    g_iWeaponStats[attacker][idx][LOG_DAMAGE] += RoundToNearest(damage);
    
    int hg = g_iNextHitgroup[victim];
    if (hg >= 0 && hg <= 7) g_iWeaponStats[attacker][idx][LOG_HIT_GENERIC + hg]++;
}

public Action Event_PlayerDeathPre(Event event, const char[] name, bool dontBroadcast) {
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));

    if (attacker > 0 && victim > 0 && attacker != victim && g_cvar_locations.BoolValue) {
        float aPos[3], vPos[3];
        GetClientAbsOrigin(attacker, aPos);
        GetClientAbsOrigin(victim, vPos);
        LogToGame("\"%L\" triggered \"interact\" with \"%L\" (attacker_position \"%d %d %d\") (victim_position \"%d %d %d\")", 
            attacker, victim, RoundFloat(aPos[0]), RoundFloat(aPos[1]), RoundFloat(aPos[2]), RoundFloat(vPos[0]), RoundFloat(vPos[1]), RoundFloat(vPos[2]));
    }
    return Plugin_Continue;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    char weaponName[32];
    event.GetString("weapon", weaponName, sizeof(weaponName));
    int idx = GetMapWeaponIndex(weaponName);
    
    if (attacker > 0 && attacker != victim && idx != -1) {
        g_iWeaponStats[attacker][idx][LOG_KILLS]++;
        g_iWeaponStats[victim][idx][LOG_DEATHS]++;
        if (g_iNextHitgroup[victim] == 1) g_iWeaponStats[attacker][idx][LOG_HEADSHOTS]++;
    }
    if (victim > 0) DumpPlayerStats(victim);
    g_iNextHitgroup[victim] = 0;
}

int GetMapWeaponIndex(const char[] weapon) {
    int idx; char buffer[32]; strcopy(buffer, sizeof(buffer), weapon);
    if (StrContains(buffer, "weapon_") == 0) strcopy(buffer, sizeof(buffer), buffer[7]);
    if (StrEqual(buffer, "physics") || StrEqual(buffer, "prop_physics")) return 8;
    if (StrEqual(buffer, "combine_ball")) return 9;
    if (StrEqual(buffer, "rpg_missile") || StrEqual(buffer, "rpg")) return 11;
    if (g_hWeaponMap.GetValue(buffer, idx)) return idx;
    return -1;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0) ResetPlayerStats(client);
}

void ResetPlayerStats(int client) {
    for (int w = 0; w < WEAPON_COUNT; w++) for (int s = 0; s < STATS_COUNT; s++) g_iWeaponStats[client][w][s] = 0;
}

void DumpPlayerStats(int client) {
    if (!IsClientInGame(client) || IsFakeClient(client)) return;
    for (int i = 0; i < WEAPON_COUNT; i++) {
        if (g_iWeaponStats[client][i][LOG_SHOTS] > 0 || g_iWeaponStats[client][i][LOG_HITS] > 0) {
            LogToGame("\"%L\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (skill_hits \"%d\") (kills \"%d\") (headshots \"%d\") (damage \"%d\")", 
                client, g_szWeaponList[i], g_iWeaponStats[client][i][LOG_SHOTS], g_iWeaponStats[client][i][LOG_HITS], g_iWeaponStats[client][i][LOG_SKILL_HITS], 
                g_iWeaponStats[client][i][LOG_KILLS], g_iWeaponStats[client][i][LOG_HEADSHOTS], g_iWeaponStats[client][i][LOG_DAMAGE]);
            LogToGame("\"%L\" triggered \"weaponstats2\" (weapon \"%s\") (head \"%d\") (chest \"%d\") (stomach \"%d\") (leftarm \"%d\") (rightarm \"%d\") (leftleg \"%d\") (rightleg \"%d\")", 
                client, g_szWeaponList[i], g_iWeaponStats[client][i][LOG_HIT_HEAD], g_iWeaponStats[client][i][LOG_HIT_CHEST], g_iWeaponStats[client][i][LOG_HIT_STOMACH], 
                g_iWeaponStats[client][i][LOG_HIT_LEFTARM], g_iWeaponStats[client][i][LOG_HIT_RIGHTARM], g_iWeaponStats[client][i][LOG_HIT_LEFTLEG], g_iWeaponStats[client][i][LOG_HIT_RIGHTLEG]);
        }
    }
    ResetPlayerStats(client);
}