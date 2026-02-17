#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

init()
{
	// Skip if enhanced promod already handles FPS boost natively
	if (getDvar("promod_version") == "enhanced_v3.3")
		return;

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
		player thread watchToggle();
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
		self setBoostDvars(true);
		self iPrintln("^7FPS Boost ^2On");
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

	self notifyOnPlayerCommand("toggle_fpsboost", "+actionslot 1");
	self _SetActionSlot(1, "");

	for(;;)
	{
		self waittill("toggle_fpsboost");

		if (isDefined(self.fpsBoostCooldown))
			continue;

		self.fpsBoostCooldown = true;

		self.pers["fpsBoost"] = !self.pers["fpsBoost"];
		self setBoostDvars(self.pers["fpsBoost"]);
		self playLocalSound("claymore_activated");

		if (self.pers["fpsBoost"])
			self iPrintlnBold("^7FPS Boost ^2On");
		else
			self iPrintlnBold("^7FPS Boost ^1Off");

		wait 0.5;
		self.fpsBoostCooldown = undefined;
	}
}

setBoostDvars(enabled)
{
	if (enabled)
	{
		self SetClientDvar("r_fullbright", 1);
		self SetClientDvar("r_fog", 0);
		self SetClientDvar("r_detailMap", 0);
		self SetClientDvar("r_glow_allowed", 0);
		self SetClientDvar("r_drawdecals", 0);
	}
	else
	{
		self SetClientDvar("r_fullbright", 0);
		self SetClientDvar("r_fog", 1);
		self SetClientDvar("r_detailMap", 1);
		self SetClientDvar("r_glow_allowed", 1);
		self SetClientDvar("r_drawdecals", 1);
	}
}
