# ozfortress ban enforcement

This SourceMod plugin for Team Fortress 2 is intended for server providers partnering with ozfortress to offer supported servers for ozfortress competitions.

By default, when a player connects to a server running this plugin, all players will be alerted if the player has been banned from ozfortress (configurable, see below). Once a convar has been enabled, these bans will be enforced. This convar will be enabled in all ozfortress configs.

## Convars

`ozf_bans_warn <0/1>` - Warn players in the chat when a banned user joins the game. Default: 1.

Note - We do not warn the entire server if a player is comms banned, but we do alert the individual in question.

`ozf_bans_enforce <0/1>` - Kick players who are currently banned from ozfortress competitions, whether they are currently in the server or just joining. Default: 0

`ozf_bans_enforce_comms <0/1>` - Mute/Gag players who are currently comms banned from ozfortress competitions, whether they are currently in the server or just joining. Changing this from 1 to 0 will unmute/ungag all players in the server. Default 0

Additionally, changing the above convars from 0 to 1 will re-trigger all their checks. Meaning if you were to turn on enforcement mid game, any users currently banned from ozfortress will be immediately kicked.