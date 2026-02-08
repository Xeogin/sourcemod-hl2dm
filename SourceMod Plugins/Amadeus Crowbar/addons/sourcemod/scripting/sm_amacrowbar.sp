#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

ConVar g_cvCrowbarDmg;
ConVar g_cvStunstickDmg;

float g_fCrowbarDamage;
float g_fStunstickDamage;

public Plugin myinfo = 
{
    name = "Amadeus Crowbar Plugin",
    author = "OriginalHappyCamper",
    description = "HL2DM Melee Dmg Override",
    version = "1.1",
};

public void OnPluginStart()
{
    CreateConVar("sm_amacrowbar_version", "1.1", "Amadeus Crowbar Plugin: Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    g_cvCrowbarDmg = CreateConVar("sm_ama_crowbar_dmg", "34.0", "Damage for one crowbar hit.", 0, true, 1.0, true, 500.0);
    g_cvStunstickDmg = CreateConVar("sm_ama_stunstick_dmg", "50.0", "Damage for one stunstick hit.", 0, true, 1.0, true, 500.0);
    
    g_fCrowbarDamage = g_cvCrowbarDmg.FloatValue;
    g_fStunstickDamage = g_cvStunstickDmg.FloatValue;
    
    g_cvCrowbarDmg.AddChangeHook(OnCvarChanged);
    g_cvStunstickDmg.AddChangeHook(OnCvarChanged);
    
    AutoExecConfig(true, "sm_amacrowbar");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    // Attacker must be a valid player
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        // For melee hits, the inflictor is usually the attacker themselves.
        // If the inflictor is a barrel (not the attacker), we skip this.
        if (inflictor == attacker)
        {
            char wepname[32];
            GetClientWeapon(attacker, wepname, sizeof(wepname));

            if (StrEqual(wepname, "weapon_crowbar", false))
            {
                damage = g_fCrowbarDamage;
                return Plugin_Changed;
            }
            else if (StrEqual(wepname, "weapon_stunstick", false))
            {
                damage = g_fStunstickDamage;
                return Plugin_Changed;
            }
        }
    }
    return Plugin_Continue;
}

public void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_cvCrowbarDmg)
        g_fCrowbarDamage = StringToFloat(newValue);
    else if (convar == g_cvStunstickDmg)
        g_fStunstickDamage = StringToFloat(newValue);
}