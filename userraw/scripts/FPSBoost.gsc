#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

init()
{
	setDvarIfUninitialized("scr_allowFPSBoost", true);
	level.allowFPSBoost = getDvarInt("scr_allowFPSBoost");

	if (level.allowFPSBoost)
		level thread onPlayerConnect();
}

onPlayerConnect()
{
	for(;;)
	{
		level waittill("connected", player);

		if (isDefined(player.pers["isBot"]) && player.pers["isBot"])
			continue;

		player.pers["fpsBoost"] = false;
		player.pers["fpsBoostMsg"] = false;
		player thread onPlayerGiveLoadout();
	}
}

onPlayerGiveLoadout()
{
	self endon("disconnect");

	for(;;)
	{
		self waittill("giveLoadout");
		self thread showMessage();
		self thread watchToggle();
	}
}

showMessage()
{
	self endon("disconnect");
	self endon("giveLoadout");
	self endon("death");

	if (self.pers["fpsBoostMsg"])
		return;

	self.pers["fpsBoostMsg"] = true;
	wait 2;
	self iPrintlnBold("^7Press ^3[{+actionslot 1}] ^7to toggle ^3FPS Boost");
}

watchToggle()
{
	self endon("disconnect");
	self endon("giveLoadout");
	self endon("death");

	self notifyOnPlayerCommand("toggle_fpsboost", "+actionslot 1");
	self _SetActionSlot(1, "");

	for(;;)
	{
		self waittill("toggle_fpsboost");

		self playLocalSound("claymore_activated");

		if (self.pers["fpsBoost"])
		{
			self SetClientDvar("r_fullbright", 0);
			self SetClientDvar("r_fog", 1);
			self SetClientDvar("r_detailMap", 1);
			self iPrintlnBold("^7FPS Boost ^1Off");
			self.pers["fpsBoost"] = false;
		}
		else
		{
			self SetClientDvar("r_fullbright", 1);
			self SetClientDvar("r_fog", 0);
			self SetClientDvar("r_detailMap", 0);
			self iPrintlnBold("^7FPS Boost ^2On");
			self.pers["fpsBoost"] = true;
		}
	}
}
