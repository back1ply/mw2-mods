#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

/*
 * _visibility.gsc — server-side visibility enforcer
 *
 * Four flags in init() toggle each active group:
 *
 *   level.visBright   — r_fullbright (flat ambient, no shadows/specular)
 *   level.visClarity  — fog / shellshock / FX / clouds / distortion / DOF / z-feather
 *   level.visNames    — instant nametag fade-in (enemy / flashbang / friendly)
 *   level.visThermal  — ThermalVisionOn: all players glow as heat signatures
 *
 * Below the divider: every line is commented out. Uncomment to taste.
 * DVars are drawn from MW2, MW3, CoD4, WaW, BO2 — the IW3/IW4/IW5/T4/T5
 * engines share a large fraction of the rendering DVar namespace.
 * Not every DVar exists in IW4x; silent no-ops are harmless.
 *
 * Complements iw4x-visibility-inject ddraw.dll — DLL handles per-client
 * shader tinting (team colors); this script sets the server-wide baseline.
 * visThermal + DLL shader_tint = thermal glow + per-team color tint.
 *
 * If _fpsboost.gsc is also loaded and boost mode is active it overlaps on
 * r_fog / r_fullbright — disable those flags in one script to avoid a race.
 */

init()
{
	level.visDelay   = 0.1;    // seconds after "spawned_player" before pushing dvars
	level.visBright  = true;   // r_fullbright: flat ambient, no shadows/specular
	level.visClarity = true;   // fog/shellshock/FX/clouds/distortion/DOF/z-feather off
	level.visNames   = true;   // nametags: instant fade-in
	level.visThermal = false;  // ThermalVisionOn: blurry/distorted — off by default

	level thread onPlayerConnect();
}

onPlayerConnect()
{
	for(;;)
	{
		level waittill("connected", player);

		if (isDefined(player.pers["isBot"]) && player.pers["isBot"])
			continue;

		player thread onPlayerSpawned();
	}
}

onPlayerSpawned()
{
	self endon("disconnect");

	for(;;)
	{
		self waittill("spawned_player");
		self thread pushVisibilityDvars();
	}
}

pushVisibilityDvars()
{
	self endon("disconnect");
	self endon("death");

	wait level.visDelay;

	// ── Active: brightness ────────────────────────────────────────────────────
	if (level.visBright)
		self SetClientDvar("r_fullbright", 1);

	// ── Active: clarity ───────────────────────────────────────────────────────
	if (level.visClarity)
	{
		self SetClientDvar("r_fog",             0);   // distance fog off
		self SetClientDvar("cg_drawShellshock", 0);   // flashbang/explosion screen distortion off
		self SetClientDvar("fx_draw",           0);   // all particle FX off (smoke/fire/explosions)
		self SetClientDvar("fx_drawClouds",     0);   // cloud/smoke billboard FX off
		self SetClientDvar("r_distortion",      0);   // heat-haze / refraction off
		self SetClientDvar("r_dof_enable",      0);   // depth-of-field blur off
		self SetClientDvar("r_zFeather",        0);   // soft-particle edge feathering off
	}

	// ── Active: names ─────────────────────────────────────────────────────────
	if (level.visNames)
	{
		self SetClientDvar("cg_enemyNameFadeIn",     0);   // enemy names appear instantly
		self SetClientDvar("cg_flashbangNameFadeIn", 0);   // friendly names reappear instantly post-flash
		self SetClientDvar("cg_friendlyNameFadeIn",  0);   // friendly names appear instantly
	}

	// ── Active: thermal player highlight ─────────────────────────────────────
	// ThermalVisionOn() is the same native call used by the in-game thermal-scope
	// perk (specialty_thermal / _perkfunctions.gsc setThermal). Applied here it
	// gives every connected player a permanent thermal overlay: player bodies glow
	// bright white/orange as heat sources; the environment cools to dark grey/blue.
	// No custom textures, no wallhack (heat sig only on visible geometry).
	// Pairs well with the ddraw.dll shader_tint (team colors) — thermal makes
	// players pop; the DLL adds red/green team differentiation on top.
	// Disable with level.visThermal = false in init() if too disorienting.
	if (level.visThermal)
		self ThermalVisionOn();


	// ═════════════════════════════════════════════════════════════════════════
	// Commented out — uncomment any line to enable
	// Sources: MW2 / MW3 / CoD4 / WaW / BO2 community configs + dvar lists.
	// IW3/4/5 and T4/T5 share most rendering dvars; silent no-ops are harmless.
	// ═════════════════════════════════════════════════════════════════════════

	// ── Sun / glare killers (outdoor maps: Wasteland, Underpass, Quarry) ─────
	// self SetClientDvar("r_sunblind_max_darken",  0);   // no screen-darkening when looking at sun
	// self SetClientDvar("r_sunflare_max_alpha",   0);   // no sun flare lens bloom
	// self SetClientDvar("r_sunglare_max_lighten", 0);   // no glare wash-out

	// ── Sun / sky tweaks (IW5 / shared with IW4 in places) ───────────────────
	// self SetClientDvar("r_lightTweakSunLight",     2);          // sunlight strength (default varies per map)
	// self SetClientDvar("r_lightTweakSunColor", "1 1 1 1");      // sun colour RGBA — white = neutral
	// self SetClientDvar("r_sky_intensity_factor0", 1);           // skybox brightness (0 = black sky)
	// self SetClientDvar("r_sky_intensity_factor1", 1);           // keep equal to factor0

	// ── Film / colour grade ───────────────────────────────────────────────────
	// self SetClientDvar("r_filmTweakEnable",       0);     // remove cinematic dark/tinted colour grade
	// -- OR keep enabled and tune individual channels:
	// self SetClientDvar("r_filmTweakEnable",         1);
	// self SetClientDvar("r_filmTweakDesaturation",   0);   // full vivid colours (default 0.2)
	// self SetClientDvar("r_filmTweakBrightness",  0.15);   // lift shadow areas (default 0)
	// self SetClientDvar("r_filmTweakContrast",     1.0);   // reduce contrast (default 1.4)

	// ── Surface quality / shading ─────────────────────────────────────────────
	// self SetClientDvar("r_specular",          0);   // no specular/shiny surfaces — flatter + FPS
	// self SetClientDvar("r_normal",            0);   // no normal maps (bumpy surfaces) — FPS
	// self SetClientDvar("r_heroLighting",      0);   // no special per-player fill light — FPS
	// self SetClientDvar("r_glow_allowed",      0);   // no glow halos — FPS
	// self SetClientDvar("r_envMapMaxIntensity", 0);  // kill env-map reflections — FPS
	// self SetClientDvar("r_fastSkin",          1);   // faster skin shader path — FPS (MW3/CoD4)

	// ── SSAO / bloom ─────────────────────────────────────────────────────────
	// self SetClientDvar("r_ssao",              0);   // disable ambient occlusion — brighter + FPS
	// self SetClientDvar("r_ssaoIntensity",     0);   // AO intensity (0 = off, keeps r_ssao at default)
	// self SetClientDvar("r_bloomTweaks",       0);   // disable bloom tweaks (BO2/IW5 — may no-op in IW4)

	// ── Anti-aliasing / render quality ────────────────────────────────────────
	// self SetClientDvar("r_aaSamples",         0);   // no MSAA — significant FPS gain, jagged edges
	// self SetClientDvar("r_aaAlpha",           0);   // no alpha anti-aliasing — FPS
	// self SetClientDvar("r_blur_allowed",      0);   // disable motion/speed blur — MW3/IW5
	// self SetClientDvar("r_depthPrepass",      0);   // skip depth pre-pass — FPS (may cause glitches)

	// ── Texture filtering ─────────────────────────────────────────────────────
	// self SetClientDvar("r_texFilterAnisoMax",   4);  // cap anisotropy — lower = FPS, higher = clarity
	// self SetClientDvar("r_texFilterMipMode", "Unchanged"); // force a specific mip blend mode

	// ── Dynamic shadows and lights ────────────────────────────────────────────
	// self SetClientDvar("r_spotLightShadows",       0);   // no spot-light cast shadows
	// self SetClientDvar("r_spotLightEntityShadows", 0);   // no entity spot-light shadows
	// self SetClientDvar("r_dlightLimit",            0);   // no dynamic lights — big FPS gain

	// ── Draw distance / culling ───────────────────────────────────────────────
	// self SetClientDvar("r_zfar",              0);   // disable distance-fog culling (0 = no limit)
	// self SetClientDvar("r_flameFX_enable",    0);   // disable flame volumetric FX — MW3/CoD4

	// ── LOD distances ─────────────────────────────────────────────────────────
	// self SetClientDvar("r_lodBiasRigid",    -1000); // keep static meshes high-res further away
	// self SetClientDvar("r_lodBiasSkinned",  -1000); // keep player/character meshes high-res further away
	// self SetClientDvar("r_lodScaleRigid",      0);  // 0 = highest quality at all distances
	// self SetClientDvar("r_lodScaleSkinned",    0);  // 0 = highest quality for players at all distances
	// self SetClientDvar("r_autoLodScale",       0);  // disable FPS-based auto LOD degradation

	// ── FOV / gun position ────────────────────────────────────────────────────
	// self SetClientDvar("cg_fov",          80);  // wider field of view (default 65, max ~80)
	// self SetClientDvar("cg_fovScale",  1.125);  // FOV multiplier on top of cg_fov (promod standard)
	// self SetClientDvar("cg_gun_x",         0);  // gun forward/back offset
	// self SetClientDvar("cg_gun_y",         0);  // gun left/right offset
	// self SetClientDvar("cg_gun_z",         0);  // gun up/down offset
	// self SetClientDvar("cg_drawGun",       0);  // hide viewmodel entirely

	// ── Overhead name tag visibility ──────────────────────────────────────────
	// self SetClientDvar("cg_overheadNamesSize", 1.5);  // larger name tags (default 0.5) — more readable
	// self SetClientDvar("cg_overheadIconSize",    0);  // hide overhead rank/status icons (less clutter)
	// self SetClientDvar("cg_overheadRankSize",    0);  // hide overhead rank number

	// ── Team colours (can make enemies/friendlies stand out more on the map) ──
	// self SetClientDvar("g_TeamColor_Axis",   "1 0 0 1");           // Axis bright red
	// self SetClientDvar("g_TeamColor_Allies", "0 1 0 1");            // Allies bright green

	// ── Visual clutter ────────────────────────────────────────────────────────
	// self SetClientDvar("cg_blood",               0);  // no blood splatter
	// self SetClientDvar("cg_brass",               0);  // no ejected shell casings
	// self SetClientDvar("ragdoll_enable",          0);  // no ragdoll physics — less noise + FPS
	// self SetClientDvar("ragdoll_fps",            10);  // reduce ragdoll simulation rate — FPS
	// self SetClientDvar("ragdoll_max_simulating",  4);  // cap simultaneous ragdolls

	// ── Fun / misc ────────────────────────────────────────────────────────────
	// self SetClientDvar("scr_thirdPerson",          1);  // force third-person view for all
	// self SetClientDvar("phys_gravity_ragdoll",   -10);  // low-gravity ragdolls (matrix effect)
	// self SetClientDvar("nightVisionDisableEffects", 1); // remove NV green overlay if goggles used
	// self SetClientDvar("cg_laserForceOn",          1);  // force laser sight visible on all weapons

	// ── Alternative vision profiles (use instead of ThermalVisionOn) ─────────
	// VisionSetNakedForPlayer applies a named .vision file to this player's view.
	// Transition time 0 = instant; >0 = smooth fade (seconds).
	// All names below are built-in IW4 vision sets — no custom files needed.
	//
	// self VisionSetNakedForPlayer("thermal_mp",  0);  // thermal scope palette (same as ThermalVisionOn)
	// self VisionSetNakedForPlayer("end_game",    0);  // bright saturated end-of-match look
	// self VisionSetNakedForPlayer("black_bw",    0);  // black-and-white (used by blast shield toggle)
	// self VisionSetNakedForPlayer(getDvar("mapname"), 0); // revert to map default (undo any override)
}
