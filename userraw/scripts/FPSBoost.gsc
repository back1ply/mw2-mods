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

		if (!isDefined(player.pers["fpsBoost"]))
			player.pers["fpsBoost"] = false;

		if (!isDefined(player.pers["fpsBoostMsg"]))
			player.pers["fpsBoostMsg"] = false;

		player thread onPlayerSpawned();
	}
}

onPlayerSpawned()
{
	self endon("disconnect");

	for(;;)
	{
		self waittill("spawned_player");
		self thread applyFPSBoost();
		self thread showMessage();
		self thread watchToggle();
	}
}

applyFPSBoost()
{
	self endon("disconnect");
	self endon("death");

	// wait for promod's setSpawnDvars() to finish
	wait 0.1;

	if (self.pers["fpsBoost"])
	{
		self SetClientDvar("r_fullbright", 1);
		self SetClientDvar("r_fog", 0);
		self SetClientDvar("r_detailMap", 0);
	}
}

showMessage()
{
	self endon("disconnect");
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
