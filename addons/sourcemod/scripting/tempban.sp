#include <sourcemod>
#include <csgo_colors>

Database g_hDatabase;
int g_iCurrentTime;
int g_iClientCreated[MAXPLAYERS+1];
int g_iClientEnds[MAXPLAYERS+1];
char g_szNick[MAXPLAYERS+1][128];
char g_szSteamID[MAXPLAYERS+1][128];

public Plugin myinfo =
{
	name = 			"Tempban",
	author = 		"Junkes",
	description = 	"Переводит игрока в спектаторы на момент бана",
	version = 		"1.0",
	url = 			"hlmod.ru"
};

public void OnPluginStart(){
    Database.Connect(ConnectCallBack, "tempban_spec");
    RegAdminCmd("sm_tempban", Command_Tempban, ADMFLAG_BAN);
    RegAdminCmd("sm_untempban", Command_UnTempban, ADMFLAG_BAN);
    AddCommandListener(Command_CheckJoin, "jointeam");
}

public Action Command_CheckJoin(int iClient, const char[] command, args)
{
    g_iCurrentTime = GetTime();
    if(g_iClientEnds[iClient] > g_iCurrentTime)
    {
        ChangeClientTeam(iClient, 1);
        CGOPrintToChat(iClient, "{RED}[onlyawp.ru] {PURPLE}У вас мини-бан. Вы можете наблюдать!");
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

public Action Command_UnTempban(int iClient, args)
{
    if(args < 2)
    {
        CGOPrintToChat(iClient, "{RED}[onlyawp.ru] {PURPLE}!untempban NICK REASON");
        return;
    }

    char nickname[128], target_name[MAX_TARGET_LENGTH], reason[128];
    int target_list[MAXPLAYERS+1];
    bool tn_is_ml;
    int found_client = -1;

    GetCmdArg(1, nickname, sizeof(nickname));
    GetCmdArg(2, reason, sizeof(reason));
    if (ProcessTargetString(
        nickname,
        iClient, 
        target_list, 
        MAXPLAYERS, 
        COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_MULTI,
        target_name,
        sizeof(target_name),
        tn_is_ml) > 0)
    {
        found_client = target_list[0];
    }
    if(tn_is_ml)
    {
        CGOPrintToChat(iClient, "{RED}[onlyawp.ru] {PURPLE}Найдено несколько игроков!")
        return;
    }

    if(found_client < 0)
    {
        ReplyToCommand(iClient, "[onlyawp.ru] Игрок не найден.");
        return;
    }
    if(g_iClientEnds[found_client] == 0){
        CGOPrintToChat(iClient, "{RED}[onlyawp.ru] {PURPLE}Игрок не забанен!");
        return;
    }
    g_iClientEnds[found_client] = 0;
    
    char sQuery[128], szAdminAuthId[128], szAuth[128];
    char szAdminNick[128], szPlayerNick[128];
    GetClientAuthId(found_client, AuthId_Engine, szAuth, sizeof(szAuth), true)
    GetClientAuthId(iClient, AuthId_Engine, szAdminAuthId, sizeof(szAdminAuthId), true);
    Format(sQuery, sizeof(sQuery), "UPDATE `bans` SET `RemovedBy` = '%s', `ureason` = '%s', `ends` = '0' WHERE `authid` = '%s' ORDER BY `bid` DESC LIMIT 1;", szAdminAuthId, reason, szAuth);
    g_hDatabase.Query(SQL_Callback_CheckError, sQuery);
    ChangeClientTeam(found_client, 2);
    GetClientName(iClient, szAdminNick, sizeof(szAdminNick));
    GetClientName(found_client, szPlayerNick, sizeof(szPlayerNick));
    CGOPrintToChatAll("{PURPLE}Администратор {RED}%s {PURPLE}снял временную блокировку с {RED}%s.", szAdminNick, szPlayerNick, reason);
}

public void OnClientDisconnect(int iClient){
    g_iClientEnds[iClient] = 0;
    g_iClientCreated[iClient] = 0;
    g_szNick[iClient] = "";
    g_szSteamID[iClient] = "";
}

public void ConnectCallBack (Database hDB, const char[] szError, any data)
{   
    if (hDB == null || szError[0])
    {
        SetFailState("Database failure: %s", szError);
        return;
    }

    g_hDatabase = hDB;
    SQL_LockDatabase(g_hDatabase);
    g_hDatabase.Query(SQL_Callback_CheckError,	"CREATE TABLE `bans` (\
                                                    `bid` INT(6) NOT NULL AUTO_INCREMENT,\
                                                    `authid` VARCHAR(64) NOT NULL DEFAULT '' COLLATE 'utf8_general_ci',\
                                                    `name` VARCHAR(128) NOT NULL DEFAULT 'unnamed' COLLATE 'utf8_general_ci',\
                                                    `created` INT(11) NOT NULL DEFAULT '0',\
                                                    `ends` INT(11) NOT NULL DEFAULT '0',\
                                                    `length` INT(10) NOT NULL DEFAULT '0',\
                                                    `reason` VARCHAR(255) NULL DEFAULT NULL COLLATE 'utf8_general_ci',\
                                                    `admin` VARCHAR(32) NOT NULL DEFAULT '' COLLATE 'utf8_general_ci',\
                                                    `RemovedBy` INT(8) NULL DEFAULT NULL,\
                                                    `ureason` MEDIUMTEXT NULL DEFAULT NULL COLLATE 'utf8_general_ci',\
                                                    PRIMARY KEY (`bid`) USING BTREE,\
                                                    FULLTEXT INDEX `reason` (`reason`),\
                                                    FULLTEXT INDEX `authid_2` (`authid`)\
                                                    )\
                                                    COLLATE='utf8_general_ci'\
                                                    ENGINE=MyISAM");
    SQL_UnlockDatabase(g_hDatabase);
    g_hDatabase.SetCharset("utf8");
}

public void OnClientPostAdminCheck(int iClient)
{
	if(!IsFakeClient(iClient))
	{
		char szQuery[256], szAuth[32];
		GetClientAuthId(iClient, AuthId_Engine, szAuth, sizeof(szAuth), true);
		FormatEx(szQuery, sizeof(szQuery), "SELECT * FROM `bans` WHERE `authid` = '%s' ORDER BY `bid` DESC LIMIT 1;", szAuth);
		g_hDatabase.Query(SQL_Callback_SelectClient, szQuery, GetClientUserId(iClient));
	}
}

public void SQL_Callback_SelectClient(Database hDatabase, DBResultSet hResults, const char[] sError, any iUserID)
{
	if(sError[0])
	{
		LogError("SQL_Callback_SelectClient: %s", sError);
		return;
	}
	
	int iClient = GetClientOfUserId(iUserID);
	if(iClient)
	{
        char szQuery[256], szName[MAX_NAME_LENGTH*2+1];
        GetClientName(iClient, szQuery, MAX_NAME_LENGTH);
        g_hDatabase.Escape(szQuery, szName, sizeof(szName));
        g_iCurrentTime = GetTime();

        if(hResults.FetchRow())
        {
            hResults.FetchString(1, g_szSteamID[iClient], sizeof(g_szSteamID[]));
            hResults.FetchString(2, g_szNick[iClient], sizeof(g_szNick[]));
            g_iClientCreated[iClient] = hResults.FetchInt(3);
            g_iClientEnds[iClient] = hResults.FetchInt(4);
        }

        PrintToServer("STEAMID: %s, Nick: %s, Created: %i, Ends: %i", g_szSteamID[iClient], g_szNick[iClient], g_iClientCreated[iClient], g_iClientEnds[iClient]);
        if(g_iClientEnds[iClient] < g_iCurrentTime){
            return;
        }

	}
}

public Action Command_Tempban(int iClient, int args)
{
    char nick[128], timechar[128], reason[128], szAuth[32], szQuery[256], szName[256], szAdminAuthId[32];

    if(args < 3){
        CGOPrintToChat(iClient, "{RED}[onlyawp.ru] {PURPLE}!tempban НИК МИНУТЫ ПРИЧИНА");
        return;
    }
    GetCmdArg(1, nick, sizeof(nick));
    GetCmdArg(2, timechar, sizeof(timechar));
    GetCmdArg(3, reason, sizeof(reason));
    int time = StringToInt(timechar);
    if(time == 0)
    {
        time = 30;
    }
    StrEqual(nick, "0");

    char target_name[MAX_TARGET_LENGTH];
    int target_list[MAXPLAYERS];
    bool tn_is_ml;
    int found_client = -1;

    if (ProcessTargetString(
            nick,
            iClient, 
            target_list, 
            MAXPLAYERS, 
            COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_MULTI,
            target_name,
            sizeof(target_name),
            tn_is_ml) > 0)
    {
        found_client = target_list[0];
    }

    if(found_client < 0){
        CGOPrintToChat(iClient, "{RED}[onlyawp.ru] {PURPLE}Игрок не найден.");
        return;
    }
    if(tn_is_ml)
    {
        CGOPrintToChat(iClient, "{RED}[onlyawp.ru] {PURPLE}Найдено несколько игроков!");
        return;
    }
    GetClientAuthId(found_client, AuthId_Engine, szAuth, sizeof(szAuth), true);
    GetClientName(found_client, szName, sizeof(szName));
    GetClientAuthId(iClient, AuthId_Engine, szAdminAuthId, sizeof(szAdminAuthId), true);
    ChangeClientTeam(found_client, 1);
    g_iClientEnds[found_client] = GetTime() + time * 60;

    char szAdminNick[128], szPlayerNick[128];
    GetClientName(iClient, szAdminNick, sizeof(szAdminNick));
    GetClientName(found_client, szPlayerNick, sizeof(szPlayerNick));
    if(!IsFakeClient(found_client))
    {
        FormatEx(szQuery, sizeof(szQuery), "INSERT INTO `bans` (`authid`,`name`,`ends`,`length`,`reason`,`admin`) VALUES ('%s', '%s', UNIX_TIMESTAMP() + %d, '%i', '%s', '%s')", szAuth, szName, time * 60, time, reason, szAdminAuthId);	// Формируем запрос
        g_hDatabase.Query(SQL_Callback_CheckError, szQuery);
        CGOPrintToChatAll("{PURPLE}Администратор {RED}%s {PURPLE}выдал временную блокировку {RED}%s.", szAdminNick, szPlayerNick, reason);
    }
}


public void SQL_Callback_CheckError(Database hDatabase, DBResultSet results, const char[] szError, any data)
{
	if(szError[0])
	{
		LogError("SQL_Callback_CheckError: %s", szError);
	}
}
