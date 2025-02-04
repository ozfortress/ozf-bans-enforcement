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

public Plugin myinfo = 
{
    name = "ozfortress Bans Enforcement",
    author = "ozfortress",
    description = "Enforces bans from ozfortress on any server",
    version = "1.0.0",
    url = "https://github.com/ozfortress/ozf-bans-enforcement",
};

ConVar g_bWarn;
ConVar g_bEnforce;
Database g_dbHandle;
KeyValues g_kvDatabaseConfig;

bool g_HasWarned[MAXPLAYERS + 1];

public void OnPluginStart()
{
    g_bWarn = CreateConVar("ozf_bans_warn", "1", "Whether to warn players about bans.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_bEnforce = CreateConVar("ozf_bans_enforce", "0", "Whether to enforce bans.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    HookConVarChange(g_bWarn, ConVarChanged);
    HookConVarChange(g_bEnforce, ConVarChanged);

    g_kvDatabaseConfig = CreateKeyValues("ozf_bans_database");
    KvSetString(g_kvDatabaseConfig, "driver", "mysql");
    KvSetString(g_kvDatabaseConfig, "host", "139.99.200.223"); // database maintained by ozfortress
    KvSetString(g_kvDatabaseConfig, "database", "sourcebans");
    KvSetString(g_kvDatabaseConfig, "user", "ozf_bans_public"); // read-only user with limited scope
    KvSetString(g_kvDatabaseConfig, "pass", ""); // no password
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
            // loop all players
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientConnected(i))
                {
                    WarnClient(i);
                }
            }
        }
        else {
            // loop all players
            for (int i = 1; i <= MaxClients; i++)
            {
                g_HasWarned[i] = false;
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
                        continue; // No steam id, wait for auth
                    }
                    HandleKick(i, auth);
                }
            }
        }
    }
}

public void OnClientAuthorized(int client, const char[] auth)
{
    HandleKick(client, auth);
}

public void OnClientPutInServer(int client)
{
    char auth[64];
    bool success = GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    if (!success)
    {
        return; // No steam id, wait for auth
    }
    HandleKick(client, auth);
}

public void WarnClient(int client)
{
    if (IsClientBanned(client))
    {
        if (GetConVarBool(g_bWarn) && !g_HasWarned[client] && !GetConVarBool(g_bEnforce))
        {
            g_HasWarned[client] = true;
            char sClientName[64];
            GetClientName(client, sClientName, sizeof(sClientName));
            PrintToChatAll("%t", "ozf_bans_warn", sClientName);
        }
    }
}

public void HandleKick(int client, const char[] auth)
{
    if (IsFakeClient(client))
    {
        return; // Ignore bots
    }
    if (auth[6] != '0')
    {
        return; // No steam id, wait for put in server
    }
    WarnClient(client);
    if (GetConVarBool(g_bEnforce))
    {
        if (IsClientBanned(client))
        {
            char sClientName[64];
            GetClientName(client, sClientName, sizeof(sClientName));
            KickClient(client, "%t", "ozf_bans_kicked");
        }
    }
}
public void OnClientDisconnect(int client)
{
    // Client disconnected, clear any warnings
    g_HasWarned[client] = false;
}

bool IsClientBanned(int client)
{
    char sQuery[512];
    char steamid[32];
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
    Format(sQuery, sizeof(sQuery), "SELECT * FROM `sb_bans` WHERE `authid` = '%s' AND `RemoveType` IS NULL AND (`ends` = `created` OR `ends` > UNIX_TIMESTAMP())", steamid);
    DBResultSet result = SQL_Query(g_dbHandle, sQuery);
    if (result == INVALID_HANDLE)
    {
        CloseHandle(result);
        return false;
    }
    bool success = SQL_FetchRow(result);
    if (!success)
    {
        CloseHandle(result);
        return false;
    }
    if (success)
    {
        if (SQL_GetRowCount(result) > 0)
        {
            CloseHandle(result);
            return true;
        } else {
            CloseHandle(result);
            return false;
        }
    }
    return false;
}