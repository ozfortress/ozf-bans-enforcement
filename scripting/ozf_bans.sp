/**
 * ozfortress bans enforcement plugin
 *  by ozfortress development team
 *
 *
 * ozfortress bans enforcement plugin © 2025 by ozfortress Development Team is licensed under CC BY-NC-ND 4.0
 *
 * see included LICENSE.md for more information
 * if you have not received a copy of the license
 * please consult https://creativecommons.org/licenses/by-nc-nd/4.0/
 */

#include <sourcemod>
#include <sdktools>
#include <dbi>
#include <basecomm>

public Plugin myinfo =
{
    name        = "ozfortress Bans Enforcement",
    author      = "ozfortress",
    description = "Enforces bans, including comms bans, from ozfortress on any server",
    version     = "2.0.2",
    url         = "https://github.com/ozfortress/ozf-bans-enforcement",
};

ConVar    g_bWarn;
ConVar    g_bEnforce;
ConVar    g_bEnforceComms;
Database  g_dbHandle;
KeyValues g_kvDatabaseConfig;

bool      g_HasWarned[MAXPLAYERS + 1];
bool      g_HasCommsWarned[MAXPLAYERS + 1];

public void OnPluginStart()
{
    g_bWarn         = CreateConVar("ozf_bans_warn", "1", "Whether to warn players about bans.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_bEnforce      = CreateConVar("ozf_bans_enforce", "0", "Whether to enforce bans.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_bEnforceComms = CreateConVar("ozf_bans_enforce_comms", "0", "Whether to enforce comms bans.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    HookConVarChange(g_bWarn, ConVarChanged);
    HookConVarChange(g_bEnforce, ConVarChanged);
    HookConVarChange(g_bEnforceComms, ConVarChanged);
    g_kvDatabaseConfig = CreateKeyValues("ozf_bans_database");
    KvSetString(g_kvDatabaseConfig, "driver", "mysql");
    KvSetString(g_kvDatabaseConfig, "host", "139.99.200.223");    // database maintained by ozfortress
    KvSetString(g_kvDatabaseConfig, "database", "sourcebans");
    KvSetString(g_kvDatabaseConfig, "user", "ozf_bans_public");    // read-only user with limited scope
    KvSetString(g_kvDatabaseConfig, "pass", "");                   // no password
    KvSetString(g_kvDatabaseConfig, "port", "3306");
    KvSetString(g_kvDatabaseConfig, "timeout", "10");
    LoadTranslations("ozf_bans.phrases.txt");
    char error[256];
    g_dbHandle = SQL_ConnectCustom(g_kvDatabaseConfig, error, sizeof(error), true);
}

public void OnPluginEnd()
{
    // Plugin cleanup code here
    CloseHandle(g_dbHandle);
    CloseHandle(g_kvDatabaseConfig);
}

public void ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_bWarn)
    {
        if (StrEqual(newValue, "1"))
        {
            // check only muted players
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientConnected(i))
                {
                    CheckIfClientBannedOrMuted(i, true);
                }
            }
        }
        else {
            // loop all players
            for (int i = 1; i <= MaxClients; i++)
            {
                g_HasWarned[i]      = false;
                g_HasCommsWarned[i] = false;
            }
        }
    }
    else if (convar == g_bEnforce)
    {
        if (StrEqual(newValue, "1"))
        {
            // loop all players
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientConnected(i))
                {
                    char auth[64];
                    bool success = GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth));
                    if (!success)
                    {
                        continue;    // No steam id, wait for auth
                    }
                    CheckIfClientBannedOrMuted(i, false);
                }
            }
        }
    }
    else if (convar == g_bEnforceComms)
    {
        if (StrEqual(newValue, "1"))
        {
            // loop all players
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientConnected(i))
                {
                    char auth[64];
                    bool success = GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth));
                    if (!success)
                    {
                        continue;    // No steam id, wait for auth
                    }
                    CheckIfClientBannedOrMuted(i, true);
                }
            }
        }
        else {
            // loop all players
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientConnected(i))
                {
                    BaseComm_SetClientMute(i, false);
                    BaseComm_SetClientGag(i, false);
                }
            }
        }
    }
}

public void OnClientAuthorized(int client, const char[] auth)
{
    HandleBanAction(client, auth);
}

public void OnClientPutInServer(int client)
{
    char auth[64];
    bool success = GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    if (!success)
    {
        return;    // No steam id, wait for auth
    }
    HandleBanAction(client, auth);
}

public void HandleBanAction(int client, const char[] auth)
{
    if (IsFakeClient(client))
    {
        return;    // Ignore bots
    }
    if (auth[6] != '0')
    {
        return;    // No steam id, wait for put in server
    }
    if (GetConVarBool(g_bEnforce))
    {
        CheckIfClientBannedOrMuted(client, false);
    }
    if (GetConVarBool(g_bEnforceComms))
    {
        CheckIfClientBannedOrMuted(client, true);
    }
}

public void OnClientDisconnect(int client)
{
    g_HasWarned[client]      = false;
    g_HasCommsWarned[client] = false;
}

void IsClientBannedCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("ozf-bans: Database query error: %s", error);
        return;
    }  
    if (results == null)
    {
        LogError("ozf-bans: Database query returned no results.");
        return;
    }
    bool checkComms = data != 0;

    bool success = results.FetchRow();
    if (!success)
    {
        if (results.MoreRows == false || results.RowCount == 0){
            return;    // No ban found
        }
    }
    int authidField;
    results.FieldNameToNum("authid", authidField); // Shouldn't fail, no need to check
    int authidLength;
    authidLength = results.FetchSize(authidField);
    char authid[MAX_AUTHID_LENGTH];
    results.FetchString(authidField, authid, authidLength);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i))
        {
            continue;
        }
        char clientAuth[64];
        bool gotAuth = GetClientAuthId(i, AuthId_Steam2, clientAuth, sizeof(clientAuth));
        if (!gotAuth)
        {
            continue;    // No steam id, wait for auth
        }
        if (StrEqual(authid, clientAuth))
        {
            if (checkComms)
            {
                // last minute: Check if the convar is still enabled
                if (!GetConVarBool(g_bEnforceComms))
                {
                    return;
                }
                BaseComm_SetClientMute(i, true);
                BaseComm_SetClientGag(i, true);
                char sClientName[64];
                GetClientName(i, sClientName, sizeof(sClientName));
                if (GetConVarBool(g_bWarn) && !g_HasCommsWarned[i])
                {
                    PrintToChat(i, "%t", "ozf_bans_comms_warn", sClientName);
                    g_HasCommsWarned[i] = true;
                }
            }
            else {
                // last minute: Check if the convar is still enabled
                if (!GetConVarBool(g_bEnforce))
                {
                    return;
                }
                char sClientName[64];
                GetClientName(i, sClientName, sizeof(sClientName));
                KickClient(i, "%t", "ozf_bans_kicked");
                if (GetConVarBool(g_bWarn))
                {
                    PrintToChatAll("%t", "ozf_bans_warn", sClientName);
                }
            }
        }
    }
}

void CheckIfClientBannedOrMuted(int client, bool checkComms = false)
{
    char sQuery[512];
    char steamid[32];
    char table[16];
    if (checkComms)
    {
        Format(table, sizeof(table), "sb_comms");
    } else {
        Format(table, sizeof(table), "sb_bans");
    }
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
    Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s` WHERE `authid` = '%s' AND `RemoveType` IS NULL AND (`ends` = `created` OR `ends` > UNIX_TIMESTAMP())", table, steamid);
    g_dbHandle.Query(IsClientBannedCallback, sQuery, checkComms, DBPrio_Normal);
}