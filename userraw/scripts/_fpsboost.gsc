#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

init()
{
	level.allowFPSBoost = true;

	/*
	 * How long to wait after "spawned_player" before applying dvars.
	 * Default 0.2s — enough for any mod's setSpawnDvars() to finish first,
	 * so we always win the ordering race without knowing what mod is loaded.
	 * Raise this on the server if a mod needs more time.
	 */
	level.fpsBoostDelay = 0.2;

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

		// Initialize FPS boost state if not set (persists across spawns/death)
		if (!isDefined(player.fpsBoostEnabled))
			player.fpsBoostEnabled = false;

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

	// Wait out any mod's spawn dvar handler before applying ours
	wait level.fpsBoostDelay;

	if (self.fpsBoostEnabled)
	{
		self setBoostDvars(true);
		self iPrintln("^7FPS Boost ^2On");
	}
}

showMessage()
{
	self endon("disconnect");
	self endon("death");

	if (isDefined(self.fpsBoostMsgShown))
		return;

	self.fpsBoostMsgShown = true;
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

		self.fpsBoostEnabled = !self.fpsBoostEnabled;
		self setBoostDvars(self.fpsBoostEnabled);
		self playLocalSound("claymore_activated");

		if (self.fpsBoostEnabled)
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
		self SetClientDvar("r_detailMap", 0);
		self SetClientDvar("r_fog", 0);
		self SetClientDvar("r_glow_allowed", 0);
		self SetClientDvar("r_drawdecals", 0);
	}
	else
	{
		self SetClientDvar("r_fullbright", 0);
		self SetClientDvar("r_detailMap", 1);
		self SetClientDvar("r_fog", 1);
		self SetClientDvar("r_glow_allowed", 1);
		self SetClientDvar("r_drawdecals", 1);
	}
}
