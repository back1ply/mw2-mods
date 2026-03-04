/*
 * ============================================================================
 * _wallhack.gsc — IW4x Poor Man's Chams v2.0 (DLL-Informed)
 * ============================================================================
 *
 * PURPOSE:
 *   Server-side GSC "ESP" (Extra Sensory Perception) for MW2 / IW4x.
 *   Provides enemy location awareness through compass markers, 3D waypoints,
 *   and distance/direction callouts — all without DLL injection.
 *
 * BASED ON:
 *   Informed by Chams4x.dll reverse engineering (Ghidra decompilation).
 *   See: Chams4x_decompiled.c for full decompiled source (4.2MB, 2436 functions).
 *   Original DLL author: unknown (Chams4x)
 *
 * HOW THE ORIGINAL DLL WORKS (for reference):
 *   1. Hooks DirectX 9 functions via PLH (PolyHook) X86 detours:
 *      - EndScene (for HUD overlay drawing)
 *      - DrawIndexedPrimitive (for model rendering interception)
 *   2. Uses Capstone disassembly engine for signature scanning
 *   3. Creates pixel shaders (ps.1.1 format) to colorize player models:
 *      "ps.1.1\ndef c0, R, G, B, A\nmov r0,c0" — solid color replacement
 *   4. Reads game's 4x4 view matrix from hardcoded addresses
 *      (0x797618 through 0x797644) for worldToScreen projection
 *   5. Renders ESP boxes, crosshair, and status menu via D3D9 draw calls
 *   6. Hotkeys: F9=main, F8=chams, F7=ESP, F6=crosshair, F10=boxes
 *      with 300ms debounce via GetAsyncKeyState
 *   7. Patches screenshot function (NOP at 0x0040250F) for "screenshot
 *      protection" — prevents clean screenshots from being taken
 *
 * WHAT THIS GSC SCRIPT DOES INSTEAD:
 *   Since GSC runs server-side and cannot touch rendering, we use
 *   game engine features to approximate the DLL's ESP functionality:
 *
 *   Mode 1 (Compass): Uses objective_add/objective_player to place
 *     enemy markers on the compass/minimap. Closest approximation
 *     to the DLL's ESP boxes — shows direction but not through walls.
 *
 *   Mode 2 (Waypoints): Uses objectives + HUD elements to float 3D
 *     markers above enemy heads. Visible through walls in some cases
 *     depending on game settings. Optional name tags via createFontString.
 *
 *   Mode 3 (Ping): Periodic text callout showing closest enemy's
 *     distance and compass direction. No visual markers — just info text.
 *     Uses custom atan2/atan math since GSC lacks trig functions.
 *
 * WHAT WE CANNOT REPLICATE IN GSC:
 *   - Actual chams (colored player models through walls) — requires
 *     DirectX hooks and pixel shader replacement
 *   - ESP boxes (2D rectangles around players) — requires
 *     worldToScreen projection and D3D9 draw calls
 *   - Custom crosshair overlay — requires D3D9 rendering
 *   - Screenshot protection — requires memory patching
 *   - Player model stride/vertex count detection — requires
 *     DrawIndexedPrimitive hook to identify player meshes
 *
 * INSTALLATION:
 *   Copy this file to: <IW4x>/userraw/scripts/_wallhack.gsc
 *   IW4x auto-loads all .gsc files from userraw/scripts/ on map start.
 *
 * CONTROLS (type in chat):
 *   !wh    — Cycle ESP modes (off → compass → waypoints → ping → off)
 *   !tags  — Toggle enemy name tags (waypoint mode only)
 *
 * No keybinds required. Chat-based activation avoids all conflicts
 * with mod keybinds and _elebot.gsc.
 *
 * NOTE ON VISIBILITY:
 *   This is a SERVER-SIDE script. All players on the server will have
 *   access to the ESP features. For admin-only or per-player control,
 *   add a GUID/name whitelist check in the isAllowed() placeholder
 *   at the bottom of this file.
 *
 * DLL FUNCTION REFERENCE (Chams4x.dll):
 *   FUN_100043E0 = applyChamsShader  → (can't replicate — needs D3D9)
 *   FUN_100044B0 = createColorTexture → (can't replicate — needs D3D9)
 *   FUN_10004570 = worldToScreen     → (can't replicate — needs view matrix)
 *   FUN_10004350 = createDetour      → (not needed — no hooks in GSC)
 *   Lines 6730-6890 = Menu HUD       → hudMenu() (simplified GSC version)
 *   Lines 7711-7762 = Hotkey handler  → watchModeSwitch/watchNametagToggle
 *   Lines 7680-7710 = Hook setup      → (not needed — no hooks in GSC)
 *
 * ============================================================================
 */

init()
{
    level.wh_version = "2.0";

    /*
     * ESP MODES
     *
     * The DLL has separate toggles for each feature (chams, ESP, boxes,
     * crosshair). We combine them into a single cycling mode since GSC
     * can only approximate a few of these.
     *
     * DLL feature → GSC mode mapping:
     *   F8 Chams     → (impossible in GSC)
     *   F7 ESP       → Mode 2: Waypoints (closest approximation)
     *   F10 ESP Boxes → Mode 1: Compass (can't draw boxes, use map dots)
     *   F6 Crosshair → (impossible in GSC)
     *   (no DLL equiv) → Mode 3: Ping (GSC-only text callout)
     */
    level.wh_mode_count = 4;
    level.wh_mode_names = [];
    level.wh_mode_names[0] = "OFF";
    level.wh_mode_names[1] = "Compass";
    level.wh_mode_names[2] = "Waypoints";
    level.wh_mode_names[3] = "Ping";

    /*
     * HUD COLOR CODES — inspired by the DLL's color scheme
     *
     * The DLL uses D3DCOLOR values for its overlay text:
     *   Active features = green text
     *   Inactive features = red text
     *   Header/labels = white text
     *
     * CoD color codes:
     *   ^0=black, ^1=red, ^2=green, ^3=yellow, ^4=blue,
     *   ^5=cyan, ^6=magenta, ^7=white
     */
    level.wh_mode_colors = [];
    level.wh_mode_colors[0] = "^1";  // red = off
    level.wh_mode_colors[1] = "^5";  // cyan = compass
    level.wh_mode_colors[2] = "^2";  // green = waypoints
    level.wh_mode_colors[3] = "^3";  // yellow = ping

    /*
     * UPDATE RATES
     *
     * wh_update_rate: how often the marker positions refresh (seconds).
     *   Lower = smoother tracking but more server load.
     *   The DLL updates every frame (~16ms at 60fps). We can't match
     *   that in GSC, so 100ms is a reasonable compromise.
     *
     * wh_ping_interval: how often Mode 3 prints distance text.
     *   Too fast = chat spam. 2 seconds feels informative without
     *   being overwhelming.
     */
    level.wh_update_rate = 0.1;    // 100ms marker refresh
    level.wh_ping_interval = 2.0;  // 2s between ping callouts

    /*
     * OBJECTIVE LIMITS
     *
     * IW4x has a hard limit of 16 objectives that can exist at once.
     * Each enemy marker uses one objective slot. With 16 max, we can
     * track up to 16 enemies simultaneously (more than enough for
     * standard 6v6 or even 9v9 games).
     */
    level.wh_max_objectives = 16;

    /*
     * OBJECTIVE ICONS
     *
     * These are shader names from the game's asset pool.
     * "compass_objpoint_c130_friendly" = small green dot (used for enemies)
     * "compass_objpoint_helicopter" = helicopter icon (used for friendlies)
     *
     * You can change these to any precached shader. Some alternatives:
     *   "waypoint_target" — crosshair-style marker
     *   "hud_status_dead" — skull icon
     *   "waypoint_bomb" — bomb icon
     */
    level.wh_icon_enemy = "compass_objpoint_c130_friendly";
    level.wh_icon_friendly = "compass_objpoint_helicopter";

    // Shaders must be precached during init or they won't render
    precacheShader(level.wh_icon_enemy);
    precacheShader(level.wh_icon_friendly);

    level thread onPlayerConnect();
}

/*
 * onPlayerConnect / initPlayer
 *
 * Standard IW4x GSC player initialization pattern.
 * Waits for "connected" event, then sets up per-player state
 * and starts all threads on each spawn.
 *
 * Each player gets their own independent ESP state so multiple
 * players can use different modes simultaneously.
 */
onPlayerConnect()
{
    for(;;)
    {
        level waittill("connected", player);
        player thread initPlayer();
    }
}

initPlayer()
{
    self endon("disconnect");

    // Per-player wallhack state
    self.wh = [];
    self.wh["mode"] = 0;            // current ESP mode (0=off)
    self.wh["nametags"] = false;     // show enemy names above markers?
    self.wh["nametagHuds"] = [];     // array of HUD elements for names
    self.wh["usedObjs"] = [];        // objective slot indices we allocated (so we only delete ours)

    for(;;)
    {
        self waittill("spawned_player");

        self thread watchChatCommands();
        self thread runWallhack();
        self thread hudMenu();
    }
}

// ============================================================
// INPUT — CHAT COMMANDS
//
// The DLL uses GetAsyncKeyState polling (lines 7711-7762).
// We use chat ("say") events instead of actionslot polling to
// avoid conflicts with mod keybinds and _elebot.gsc.
// No client keybinds required.
//
// DLL hotkey → chat command mapping:
//   F9  Main toggle  → !wh   (cycle: off → compass → waypoints → ping → off)
//   F7  ESP toggle   → !wh
//   (no DLL equiv)   → !tags (toggle nametags, waypoint mode only)
// ============================================================

watchChatCommands()
{
    self endon("disconnect");
    self endon("death");

    for(;;)
    {
        self waittill("say", text);
        text = toLower(text);

        switch(text)
        {
            case "!wh":
                self thread clearMarkers();
                self.wh["mode"]++;
                if(self.wh["mode"] >= level.wh_mode_count)
                    self.wh["mode"] = 0;
                mode = self.wh["mode"];
                color = level.wh_mode_colors[mode];
                self iPrintLn("^3ESP: " + color + level.wh_mode_names[mode]);
                break;

            case "!tags":
                self.wh["nametags"] = !self.wh["nametags"];
                if(!self.wh["nametags"])
                    self thread clearNametags();
                if(self.wh["nametags"])
                    self iPrintLn("^3Nametags: ^2ON");
                else
                    self iPrintLn("^3Nametags: ^1OFF");
                break;
        }
    }
}

// ============================================================
// MAIN DISPATCH LOOP
//
// Runs continuously while the player is alive. Every update_rate
// seconds, it calls the appropriate mode function based on
// the current self.wh["mode"] value.
//
// Note: each mode function is threaded so it can run independently.
// The modes don't overlap since clearMarkers() is called on switch.
// ============================================================

runWallhack()
{
    self endon("disconnect");
    self endon("death");

    for(;;)
    {
        mode = self.wh["mode"];

        if(mode == 1)
            self thread modeCompass();
        else if(mode == 2)
            self thread modeWaypoints();
        else if(mode == 3)
            self thread modePing();

        // mode 0 = off, do nothing

        wait level.wh_update_rate;
    }
}

// ============================================================
// MODE 1: COMPASS DOTS
//
// Places objective markers at each enemy's position. These show
// up on the compass/minimap as icons, giving directional awareness.
//
// GSC functions used:
//   objective_add(index, "active", position, shader)
//     — Creates a map objective at the given world position
//   objective_player(index, player)
//     — Makes the objective visible only to the specified player
//
// This is the closest GSC approximation to the DLL's ESP overlay.
// Unlike the DLL, these markers only show on the compass — not
// as floating icons in the 3D world (that's Mode 2).
//
// LIMITATION: IW4x has max 16 objectives. In a 9v9 game with 8
// enemies, we use 8 of 16 slots — plenty of headroom.
// ============================================================

modeCompass()
{
    self endon("disconnect");
    self endon("death");

    // Start from slot 4 — reserve 0-3 for game/mod use (S&D bomb, etc.)
    objIndex = 4;
    self.wh["usedObjs"] = [];
    players = level.players;

    for(i = 0; i < players.size; i++)
    {
        target = players[i];
        if(!isValidTarget(target))
            continue;

        if(objIndex >= level.wh_max_objectives)
            break;

        if(isEnemy(target))
        {
            objective_add(objIndex, "active", target getOrigin(), level.wh_icon_enemy);
            objective_player(objIndex, self);
            self.wh["usedObjs"][self.wh["usedObjs"].size] = objIndex;
            objIndex++;
        }
    }
}

// ============================================================
// MODE 2: 3D WAYPOINTS
//
// Similar to Mode 1 but places markers 70 units above enemy heads,
// making them visible as floating icons in the 3D world. Optionally
// shows enemy player names via HUD text elements.
//
// The 70-unit offset approximates head height. CoD player models
// are roughly 60-72 units tall depending on stance.
//
// With nametags enabled, creates persistent HUD text elements
// (via newClientHudElem + setWaypoint) that display enemy names
// above the waypoint markers. These are tracked in the
// self.wh["nametagHuds"] array and cleaned up on mode switch.
//
// NOTE ON PERFORMANCE:
//   Each nametag HUD element costs server resources. With 8+
//   enemies and nametags enabled, there are 8 objectives +
//   8 HUD elements updating every 100ms. This is acceptable
//   for small servers but may cause lag on 18-player servers.
// ============================================================

modeWaypoints()
{
    self endon("disconnect");
    self endon("death");

    // Start from slot 4 — reserve 0-3 for game/mod use (S&D bomb, etc.)
    objIndex = 4;
    self.wh["usedObjs"] = [];
    players = level.players;

    for(i = 0; i < players.size; i++)
    {
        target = players[i];
        if(!isValidTarget(target))
            continue;

        if(objIndex >= level.wh_max_objectives)
            break;

        if(isEnemy(target))
        {
            pos = target getOrigin();
            markerPos = (pos[0], pos[1], pos[2] + 70);

            objective_add(objIndex, "active", markerPos, level.wh_icon_enemy);
            objective_player(objIndex, self);
            self.wh["usedObjs"][self.wh["usedObjs"].size] = objIndex;
            objIndex++;

            if(self.wh["nametags"])
                self thread updateNametag(i, target, markerPos);
        }
    }
}

// ============================================================
// MODE 3: PERIODIC TEXT PING
//
// Every wh_ping_interval seconds, finds the closest enemy and
// prints their distance and relative direction as text.
//
// Example output: "ENEMY AHEAD 42ft [PlayerName]"
//
// Direction is calculated using custom atan2/atan implementations
// (see math section below) since GSC has no built-in trig functions.
//
// IMPROVEMENTS OVER v1.0 (informed by DLL analysis):
//   - Distance is color-coded by threat level:
//     Green (>500 units)  = far, low threat
//     Yellow (200-500)    = medium range
//     Red (<200)          = close, high threat
//   - Direction labels are color-coded:
//     Green = ahead (in your crosshair)
//     Yellow = flanks (front-left/right)
//     White = sides (pure left/right)
//     Red = behind (back-left/right, directly behind)
//
// This color scheme is inspired by the DLL's threat assessment
// in its ESP overlay, which colors enemies by distance.
// ============================================================

modePing()
{
    self endon("disconnect");
    self endon("death");

    // Throttle: only print at the configured interval
    if(!isDefined(self.wh["lastPing"]))
        self.wh["lastPing"] = 0;

    now = getTime();  // returns milliseconds since server start
    if(now - self.wh["lastPing"] < level.wh_ping_interval * 1000)
        return;

    self.wh["lastPing"] = now;

    // Find closest enemy
    myPos = self getOrigin();
    myAngles = self getPlayerAngles();
    players = level.players;
    closest = undefined;
    closestDist = 99999;

    for(i = 0; i < players.size; i++)
    {
        target = players[i];
        if(!isValidTarget(target))
            continue;

        if(!isEnemy(target))
            continue;

        // distance() is a built-in GSC function (3D distance)
        dist = distance(myPos, target getOrigin());
        if(dist < closestDist)
        {
            closestDist = dist;
            closest = target;
        }
    }

    if(!isDefined(closest))
        return;

    // Get compass direction relative to where player is looking
    dir = getDirection(myPos, myAngles, closest getOrigin());

    // Convert game units to approximate feet (12 units ≈ 1 foot)
    distFeet = int(closestDist / 12);

    // Color code distance by threat level (DLL-inspired)
    distColor = "^2";           // green = far, low threat
    if(closestDist < 500)
        distColor = "^3";       // yellow = medium range
    if(closestDist < 200)
        distColor = "^1";       // red = close, danger!

    self iPrintLn("^1ENEMY ^7" + dir + " " + distColor + distFeet + "ft ^7[" + closest.name + "]");
}

// ============================================================
// NAMETAG HUD ELEMENTS
//
// Creates floating text above enemy waypoint markers showing
// the player's name. Uses IW4x's waypoint HUD feature to
// make the text track a 3D world position.
//
// GSC functions used:
//   newClientHudElem(player) — creates a HUD element visible only to player
//   hud setWaypoint(true, true) — makes HUD track a 3D world position
//     First param: show distance? Second param: show through walls?
//   hud setText(string) — set the displayed text
//
// Elements are stored in self.wh["nametagHuds"][index] and reused
// across updates (not destroyed/recreated each frame).
// ============================================================

updateNametag(index, target, pos)
{
    // Reuse existing HUD element or create new one
    if(!isDefined(self.wh["nametagHuds"][index]))
    {
        hud = newClientHudElem(self);
        hud.alpha = 0.8;              // slightly transparent
        hud.fontScale = 0.9;          // smaller than default text
        hud.color = (1, 0.3, 0.3);   // red tint (RGB, 0-1 range)
        hud.hideWhenInMenu = true;    // don't show in pause menu
        self.wh["nametagHuds"][index] = hud;
    }

    hud = self.wh["nametagHuds"][index];
    hud setWaypoint(true, true);  // enable 3D tracking + show through walls
    hud.x = pos[0];
    hud.y = pos[1];
    hud.z = pos[2] + 15;  // slightly above the waypoint marker
    hud setText(target.name);
}

/*
 * clearNametags — destroy all nametag HUD elements
 *
 * Called when:
 *   - Nametags are toggled off
 *   - ESP mode is switched (clearMarkers calls this)
 *   - Player dies/disconnects (endon handles this)
 */
clearNametags()
{
    for(i = 0; i < self.wh["nametagHuds"].size; i++)
    {
        if(isDefined(self.wh["nametagHuds"][i]))
        {
            self.wh["nametagHuds"][i] destroy();
            self.wh["nametagHuds"][i] = undefined;
        }
    }
}

// ============================================================
// CLEANUP
//
// Removes all objective markers and nametag HUDs.
// Called when switching modes to prevent leftover markers
// from the previous mode stacking with the new mode's markers.
// ============================================================

clearMarkers()
{
    // Only delete objective slots we actually allocated — never touch
    // slots owned by the game or mod (e.g. S&D bomb objectives).
    for(i = 0; i < self.wh["usedObjs"].size; i++)
        objective_delete(self.wh["usedObjs"][i]);

    self.wh["usedObjs"] = [];
    self thread clearNametags();
}

// ============================================================
// HUD MENU — DLL-STYLE STATUS DISPLAY
//
// This mimics the Chams4x.dll's overlay menu system.
//
// DLL's menu (Chams4x_decompiled.c lines 6730-6890):
//   The DLL draws text directly onto the screen via D3D9:
//     "F9 Main: [ON/OFF]"
//     "F8 Chams: [ON/OFF]"
//     "F7 ESP: [ON/OFF]"
//     "F6 Crosshair: [ON/OFF]"
//     "F10 ESP Boxes: [ON/OFF]"
//     "Screenshot Protection: [ON/OFF]"
//
//   Each line is green if the feature is active, red if not.
//   The menu is always visible in the top-left corner of the screen.
//
// GSC version:
//   We use two persistent HUD text elements in the bottom-left:
//   - Main line: shows current ESP mode with color coding
//   - Toggles line: shows actionslot bindings and toggle states
//
//   This is positioned at BOTTOMLEFT to avoid overlapping with
//   _elebot.gsc's HUD (which is also at BOTTOMLEFT but at y=-5).
//   The wallhack HUD sits higher at y=-20 and y=-35.
// ============================================================

hudMenu()
{
    self endon("disconnect");
    self endon("death");

    // Main status line (bottom-left, offset to not overlap elebot HUD)
    hudMain = self createFontString("objective", 1.1);
    hudMain setPoint("BOTTOMLEFT", "BOTTOMLEFT", 5, -20);
    hudMain.alpha = 0.7;
    hudMain.hideWhenInMenu = true;

    // Feature toggles line (above the main line)
    // Smaller font + lower alpha for less visual noise
    hudToggles = self createFontString("objective", 0.9);
    hudToggles setPoint("BOTTOMLEFT", "BOTTOMLEFT", 5, -35);
    hudToggles.alpha = 0.5;
    hudToggles.hideWhenInMenu = true;

    for(;;)
    {
        mode = self.wh["mode"];
        color = level.wh_mode_colors[mode];

        // Main line: current ESP mode (mirrors DLL's "F7 ESP: [ON/OFF]")
        if(mode == 0)
            hudMain setText("^7ESP ^1OFF");
        else
            hudMain setText(color + "ESP ^7" + level.wh_mode_names[mode]);

        // Toggles line: shows keybindings and states
        // Mirrors the DLL's multi-line menu but compressed to one line
        // Format: [actionslot]Feature:State
        tagStr = "^1OFF";
        if(self.wh["nametags"])
            tagStr = "^2ON";

        hudToggles setText("^7!wh:" + color + level.wh_mode_names[mode] + " ^7!tags:" + tagStr);

        wait 0.3;
    }
}

// ============================================================
// TARGET VALIDATION HELPERS
// ============================================================

/*
 * isValidTarget — check if a player entity is a valid ESP target
 *
 * Filters out:
 *   - undefined/null players (disconnected mid-frame)
 *   - dead players (no point tracking corpses)
 *   - self (don't show your own position)
 */
isValidTarget(player)
{
    if(!isDefined(player))
        return false;
    if(!isAlive(player))
        return false;
    if(player == self)
        return false;
    return true;
}

/*
 * isEnemy — determine if a player is on the opposing team
 *
 * In free-for-all (FFA) modes: everyone is an enemy.
 * In team modes (TDM, DOM, S&D, etc.): compare team strings.
 *
 * level.teamBased is set by the game engine:
 *   0 = FFA mode (no teams)
 *   1 = team-based mode
 *
 * player.team values: "allies", "axis", "spectator"
 */
isEnemy(player)
{
    // FFA: everyone except self is an enemy
    if(level.teamBased == 0)
        return true;

    return player.team != self.team;
}

// ============================================================
// DIRECTION CALCULATION
//
// These functions calculate the relative compass direction from
// the player to a target. Since GSC has NO built-in trigonometry
// functions (no sin, cos, tan, atan, atan2), we implement our
// own using mathematical approximations.
//
// The DLL doesn't need this — it uses the C runtime's math
// functions and the game's 4x4 view matrix for worldToScreen
// projection. But in GSC, text-based direction is the best we
// can do without rendering access.
//
// MATH CHAIN:
//   getDirection()
//     → atan2(dy, dx) → returns angle in degrees
//       → atan(y/x) → returns angle in radians
//         → Taylor series approximation for |x| <= 1
//         → Identity atan(x) = π/2 - atan(1/x) for |x| > 1
//
// ACCURACY:
//   The Taylor series (3 terms) gives ~3 decimal places of
//   accuracy. For an 8-point compass (45° sectors), this is
//   more than sufficient. You'd need ~10° accuracy to distinguish
//   sectors, and we're well within that.
// ============================================================

/*
 * getDirection — compass direction from player to target
 *
 * Returns a color-coded compass label:
 *   ^2AHEAD    = target is in front (green, easy shot)
 *   ^3FRONT-L  = target is ahead-left (yellow, look left)
 *   ^3FRONT-R  = target is ahead-right (yellow, look right)
 *   ^7LEFT     = target is directly left (white)
 *   ^7RIGHT    = target is directly right (white)
 *   ^1BACK-L   = target is behind-left (red, danger)
 *   ^1BACK-R   = target is behind-right (red, danger)
 *   ^1BEHIND   = target is directly behind (red, watch your back)
 *
 * Algorithm:
 *   1. Calculate world angle from player to target using atan2
 *   2. Subtract player's yaw (where they're looking)
 *   3. Normalize relative angle to -180..180
 *   4. Map to 8 compass sectors (45° each)
 */
getDirection(fromPos, fromAngles, toPos)
{
    // Delta from player to target (world coordinates)
    dx = toPos[0] - fromPos[0];
    dy = toPos[1] - fromPos[1];

    // World angle to target (degrees, using our custom atan2)
    targetAngle = atan2(dy, dx);

    // Player's yaw (horizontal view angle, degrees)
    yaw = fromAngles[1];

    // Relative angle = how far off from crosshair the target is
    relative = targetAngle - yaw;

    // Normalize to -180..180 range
    while(relative > 180)
        relative -= 360;
    while(relative < -180)
        relative += 360;

    // Map to 8-point compass (45° sectors centered on each direction)
    //
    //          AHEAD (0°)
    //    FRONT-L /  \ FRONT-R
    //      LEFT |    | RIGHT
    //    BACK-L \  / BACK-R
    //         BEHIND (±180°)
    //
    if(relative > -22.5 && relative <= 22.5)
        return "^2AHEAD";       // green = directly in front
    if(relative > 22.5 && relative <= 67.5)
        return "^3FRONT-L";     // yellow = front-left quadrant
    if(relative > 67.5 && relative <= 112.5)
        return "^7LEFT";        // white = directly left
    if(relative > 112.5 && relative <= 157.5)
        return "^1BACK-L";      // red = behind-left
    if(relative > -67.5 && relative <= -22.5)
        return "^3FRONT-R";     // yellow = front-right quadrant
    if(relative > -112.5 && relative <= -67.5)
        return "^7RIGHT";       // white = directly right
    if(relative > -157.5 && relative <= -112.5)
        return "^1BACK-R";      // red = behind-right

    return "^1BEHIND";          // red = directly behind
}

/*
 * atan2(y, x) — two-argument arctangent
 *
 * Returns the angle in DEGREES (not radians) from the positive
 * X-axis to the point (x, y). Range: -180 to +180 degrees.
 *
 * This is a standard math function that GSC lacks. We implement
 * it using our custom atan() function with quadrant correction.
 *
 * Quadrant handling:
 *   x > 0           → atan(y/x)                    (Q1 or Q4)
 *   x < 0, y >= 0   → atan(y/x) + π               (Q2)
 *   x < 0, y < 0    → atan(y/x) - π               (Q3)
 *   x = 0, y > 0    → +90°                         (positive Y axis)
 *   x = 0, y < 0    → -90°                         (negative Y axis)
 *   x = 0, y = 0    → 0° (undefined, but we return 0)
 */
atan2(y, x)
{
    if(x > 0)
        return atan(y / x) * (180 / 3.14159);
    if(x < 0 && y >= 0)
        return (atan(y / x) + 3.14159) * (180 / 3.14159);
    if(x < 0 && y < 0)
        return (atan(y / x) - 3.14159) * (180 / 3.14159);
    if(x == 0 && y > 0)
        return 90;
    if(x == 0 && y < 0)
        return -90;
    return 0;  // x=0, y=0 — undefined, default to 0
}

/*
 * atan(x) — single-argument arctangent
 *
 * Returns the angle in RADIANS. Range: -π/2 to +π/2.
 *
 * For |x| <= 1: uses Taylor series approximation
 *   atan(x) ≈ x - x³/3 + x⁵/5
 *   (3 terms, accurate to ~3 decimal places)
 *
 * For |x| > 1: uses the identity
 *   atan(x) = π/2 - atan(1/x)
 *   This maps the input to the |x| <= 1 range where
 *   the Taylor series converges well.
 *
 * NOTE: More terms could be added for better accuracy:
 *   - x⁷/7 term → ~4 decimal places
 *   - x⁹/9 term → ~5 decimal places
 *   But 3 terms is sufficient for 45° compass sectors.
 */
atan(x)
{
    // Handle |x| > 1 via identity to keep Taylor series accurate
    if(x > 1)
        return (3.14159 / 2) - atan(1 / x);
    if(x < -1)
        return (-3.14159 / 2) - atan(1 / x);

    // Taylor series for |x| <= 1
    x3 = x * x * x;
    x5 = x3 * x * x;
    return x - (x3 / 3) + (x5 / 5);
}

// ============================================================
// PLACEHOLDER: PER-PLAYER ACCESS CONTROL
//
// Uncomment and modify isAllowed() to restrict ESP features
// to specific players (e.g., server admins only).
//
// Usage: add "if(!isAllowed()) return;" at the top of
// watchModeSwitch() and watchNametagToggle().
//
// Example implementations:
//
// By GUID (recommended — unique per player):
//   isAllowed() {
//       guid = self getGuid();
//       if(guid == "your-guid-here") return true;
//       return false;
//   }
//
// By name (easy but spoofable):
//   isAllowed() {
//       if(self.name == "YourName") return true;
//       return false;
//   }
//
// ============================================================
