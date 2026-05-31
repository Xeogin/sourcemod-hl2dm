#include <sourcemod>
#include <sdktools>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = 
{
    name = "New Player Join Sounds",
    author = "Gemini+Xeogin",
    description = "Plays a random welcome sound from a config file with per-sound volume adjustments",
    version = "1.0",
    url = ""
};

enum struct SoundEntry
{
    char path[PLATFORM_MAX_PATH];
    float volume;
    float delay;
}

ArrayList g_hSoundList;
bool g_bMapTransitioning;
bool g_bHasHeardJoinSound[MAXPLAYERS + 1];

public void OnPluginStart()
{
    HookEvent("player_activate", Event_PlayerActivate);
    g_hSoundList = new ArrayList(sizeof(SoundEntry));
}

public void OnMapStart()
{
    g_hSoundList.Clear();
    ParseSoundConfig();
    
    // Lock the gate immediately on map load
    g_bMapTransitioning = true;
    
    // Hold the gate closed for 5 seconds to clear out all transitioning players
    CreateTimer(5.0, Timer_EndMapTransition, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_EndMapTransition(Handle timer)
{
    g_bMapTransitioning = false;
    return Plugin_Stop;
}

public void OnClientDisconnect(int client)
{
    g_bHasHeardJoinSound[client] = false;
}

void ParseSoundConfig()
{
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), "configs/join_sounds.cfg");
    
    if (!FileExists(configPath))
    {
        KeyValues kvDefault = new KeyValues("JoinSounds");
        if (kvDefault.JumpToKey("Welcome", true))
        {
            kvDefault.SetString("path", "sound/connect/welcome.mp3");
            kvDefault.SetFloat("volume", 1.0);
            kvDefault.SetFloat("delay", 1.0);
        }
        kvDefault.Rewind();
        kvDefault.ExportToFile(configPath);
        delete kvDefault;
    }
    
    KeyValues kv = new KeyValues("JoinSounds");
    if (!kv.ImportFromFile(configPath))
    {
        delete kv;
        return;
    }
    
    if (kv.GotoFirstSubKey())
    {
        do
        {
            char rawPath[PLATFORM_MAX_PATH];
            char downloadPath[PLATFORM_MAX_PATH];
            char gamePath[PLATFORM_MAX_PATH];
            kv.GetString("path", rawPath, sizeof(rawPath));
            
            if (!rawPath[0]) continue;
            
            if (StrContains(rawPath, "sound/", false) == 0)
            {
                strcopy(downloadPath, sizeof(downloadPath), rawPath);
                strcopy(gamePath, sizeof(gamePath), rawPath[6]);
            }
            else
            {
                Format(downloadPath, sizeof(downloadPath), "sound/%s", rawPath);
                strcopy(gamePath, sizeof(gamePath), rawPath);
            }
            
            if (FileExists(downloadPath))
            {
                AddFileToDownloadsTable(downloadPath);
                VerifyAudioFormat(downloadPath);
                
                PrecacheSound(gamePath, true);
                PrefetchSound(gamePath);
                
                SoundEntry sound;
                sound.volume = kv.GetFloat("volume", 1.0);
                sound.delay = kv.GetFloat("delay", 1.0);
                strcopy(sound.path, sizeof(sound.path), gamePath);
                
                g_hSoundList.PushArray(sound);
            }
        } 
        while (kv.GotoNextKey(false));
    }
    delete kv;
}

void VerifyAudioFormat(const char[] relativePath)
{
    File file = OpenFile(relativePath, "rb");
    if (file == null) return;
    
    char header[5];
    file.ReadString(header, sizeof(header));
    delete file;
    
    if (StrContains(relativePath, ".mp3", false) != -1 && header[0] != 'I' && header[1] != 'D')
    {
        LogMessage("[JoinSound] Notice: Asset '%s' loaded. Ensure it is encoded at 44100Hz CBR for seamless engine playback.", relativePath);
    }
}

public void Event_PlayerActivate(Event event, const char[] name, bool dontBroadcast)
{
    if (g_hSoundList.Length == 0) return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) return;
    
    // If map transition timer is running, flag existing players as heard and skip audio
    if (g_bMapTransitioning)
    {
        g_bHasHeardJoinSound[client] = true;
        return;
    }
    
    if (g_bHasHeardJoinSound[client]) return;
    
    g_bHasHeardJoinSound[client] = true;
    
    int randomIndex = GetURandomInt() % g_hSoundList.Length;
    SoundEntry chosenSound;
    g_hSoundList.GetArray(randomIndex, chosenSound);
    
    DataPack pack;
    CreateDataTimer(chosenSound.delay, Timer_PlayJoinSound, pack, TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(chosenSound.path);
    pack.WriteFloat(chosenSound.volume);
}

public Action Timer_PlayJoinSound(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    
    if (client <= 0 || !IsClientInGame(client)) return Plugin_Stop;
    
    char path[PLATFORM_MAX_PATH];
    pack.ReadString(path, sizeof(path));
    float volume = pack.ReadFloat();
    
    EmitSoundToClient(client, path, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_NOFLAGS, volume);
    
    return Plugin_Stop;
}