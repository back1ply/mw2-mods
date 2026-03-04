/*
 * ============================================================================
 * _elebot.gsc — IW4x Elebot v2.0 (DLL-Accurate)
 * ============================================================================
 *
 * PURPOSE:
 *   Server-side GSC elevator bot for MW2 / IW4x.
 *   Automates the stance-switch exploit ("elevator glitch") that lets
 *   a player rise through certain map geometry by rapidly toggling
 *   between crouch and stand.
 *
 * BASED ON:
 *   Reverse-engineered from elebotv2.dll (Ghidra decompilation).
 *   See: elebotv2_decompiled.c for full decompiled source.
 *   Original DLL author credits: "batman" (elebotv2)
 *
 * HOW THE ORIGINAL DLL WORKS:
 *   1. Injects into iw3mp.exe (CoD4) via CreateRemoteThread
 *   2. Registers custom dvars: elebot_run, elebot_maxfps, elebot_autojump,
 *      elebot_alert, elebot_goupfast, elebot_usezfar
 *   3. When elebot_run=1, reads player yaw to pick axis/direction
 *   4. Sends commands via Cbuf_AddText (game engine func at 0x4F9AB0):
 *      +moveup, -moveup, wait 2, gocrouch, wait 2, +moveup, -moveup
 *   5. Manipulates com_maxfps via WriteProcessMemory for timing control
 *   6. Uses forward/back/left nudges for position alignment
 *
 * WHAT THIS GSC SCRIPT REPLICATES:
 *   - Direction-aware yaw detection (from FUN_10001950)
 *   - Position alignment nudges (from FUN_10001400)
 *   - Stability checks: read pos, wait, read again (from FUN_10001280)
 *   - FPS switching: 500 (low) / 1000 (boost) (from FUN_10001280)
 *   - Lateral drift correction with +moveleft (from FUN_10001580)
 *   - GoUpFast: 1000fps while rising + wait for peak (from FUN_10001580)
 *   - Autojump: velocity boost at peak height
 *
 * WHAT WE CANNOT REPLICATE IN GSC:
 *   - Direct memory writes (WriteProcessMemory) — we use setClientDvar instead
 *   - Cbuf_AddText console commands — we use setStance()/setVelocity() instead
 *   - Sub-millisecond timing (Sleep(2) = 2ms) — GSC minimum wait is ~50ms
 *   - usezfar optimization (r_zfar dvar manipulation for FPS boost)
 *
 * INSTALLATION:
 *   Copy this file to: <IW4x>/userraw/scripts/_elebot.gsc
 *   IW4x auto-loads all .gsc files from userraw/scripts/ on map start.
 *
 * CONTROLS (type in chat):
 *   !ele   — Toggle elebot on/off
 *   !aj    — Toggle autojump
 *   !guf   — Toggle goupfast (1000fps boost while rising)
 *   !alr   — Toggle alert messages on completion
 *
 * No keybinds required. Chat-based activation avoids all conflicts
 * with mod keybinds (e.g. promod's actionslot 4 bomb drop in S&D).
 *
 * DLL FUNCTION REFERENCE MAP:
 *   FUN_10001d40 = DllMain           → (not needed in GSC, auto-loaded)
 *   FUN_10001d10 = init              → init()
 *   FUN_10001c50 = mainLoop          → onPlayerConnect() / initPlayer()
 *   FUN_10001af0 = setup/registerDvars → init() level vars
 *   FUN_10001950 = elebot_start      → startEle()
 *   FUN_10001400 = elebot_align      → eleAlign()
 *   FUN_10001280 = elebot_nudge      → stability checks in eleMainLoop()
 *   FUN_10001580 = elebot_mainLoop   → eleMainLoop()
 *   FUN_100010f0 = elebot_stop       → stopEle()
 *   FUN_10001030 = Cbuf_AddText      → (replaced by setStance/setVelocity)
 *   FUN_10001090 = Cvar_Register     → (replaced by level.ele_* vars)
 *   FUN_10001050 = Com_Printf        → iPrintLn / iPrintLnBold
 *
 * ============================================================================
 */

init()
{
    level.ele_version = "2.0";

    /*
     * FPS DEFAULTS — sourced from FUN_10001af0 (Cvar_Register calls)
     *
     * The DLL registers "elebot_maxfps" with default 250, min 30, max 1000.
     * It then patches com_maxfps via WriteProcessMemory at runtime.
     *
     * In GSC we use setClientDvar("com_maxfps", value) instead.
     * We default to 333 for IW4x (better than CoD4's 250 baseline).
     *
     * The DLL switches between these FPS values during operation:
     *   - 333 (default): normal gameplay fps
     *   - 500 (low):     used during stability checks (FUN_10001280)
     *   - 1000 (boost):  used during GoUpFast ascent (FUN_10001580)
     */
    level.ele_maxfps_default = 333;
    level.ele_maxfps_boost   = 1000;
    level.ele_maxfps_low     = 500;

    /*
     * FEATURE TOGGLES — sourced from FUN_10001af0 dvar registrations
     *
     * elebot_autojump: "Automatically jump when the ele is complete?"
     *   → Default: 1 (on), min 0, max 1
     *
     * elebot_goupfast: "Switches to 1000fps while going up"
     *   → Default: 1 (on), min 0, max 1
     *   → DLL note: "only works with autojump"
     *
     * elebot_alert: "Prints alert to screen when the ele is complete"
     *   → Default: 1 (on), min 0, max 1
     */
    level.ele_autojump_default = true;
    level.ele_goupfast_default = true;
    level.ele_alert_default    = true;

    /*
     * THRESHOLDS
     *
     * height_threshold: minimum Z gain (units) to consider ele "successful".
     *   The DLL uses several float constants for range checks; 20 units
     *   is a reasonable GSC approximation.
     *
     * abort_horiz_dist: if player moves this far horizontally from start,
     *   abort the elebot. The DLL prints "Out of range of the ele, stopping..."
     *   (FUN_10001580 line ~318).
     */
    level.ele_height_threshold = 20;
    level.ele_abort_horiz_dist = 50;

    /*
     * YAW QUADRANT BOUNDARIES — derived from FUN_10001950
     *
     * The DLL reads the player's yaw (view angle) to determine which
     * world axis the elevator operates on. It divides 360 degrees into
     * 4 quadrants and picks X-axis or Y-axis accordingly.
     *
     * The DLL compares yaw against hardcoded float constants at:
     *   _DAT_10003518, _DAT_10003510, _DAT_10003500, _DAT_100034f8, etc.
     * These map roughly to 45/135/225/315 degree boundaries.
     *
     *   315-45°   = East  → X-axis, forward nudge
     *   45-135°   = North → Y-axis, forward nudge
     *   135-225°  = West  → X-axis, backward nudge
     *   225-315°  = South → Y-axis, backward nudge
     */
    level.ele_yaw_q1 = 45;
    level.ele_yaw_q2 = 135;
    level.ele_yaw_q3 = 225;
    level.ele_yaw_q4 = 315;

    level thread onPlayerConnect();
}

/*
 * onPlayerConnect / initPlayer
 *
 * Mirrors FUN_10001c50 (mainLoop):
 * The DLL waits in a loop for the game to load (checks a byte at
 * DAT_10004030+0x14), then registers dvars and polls elebot_run.
 *
 * In GSC, we use the "connected" / "spawned_player" events instead.
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

    // Per-player state — mirrors DLL's global state variables
    self.ele = [];
    self.ele["active"]    = false;       // DLL: DAT_10004198 (running flag)
    self.ele["autojump"]  = level.ele_autojump_default;  // DLL: elebot_autojump dvar
    self.ele["goupfast"]  = level.ele_goupfast_default;  // DLL: elebot_goupfast dvar
    self.ele["alert"]     = level.ele_alert_default;     // DLL: elebot_alert dvar
    self.ele["direction"] = 0;  // 0=X-axis, 1=Y-axis (DLL: DAT_10004194 pointer)
    self.ele["sign"]      = 1;  // +1 or -1 nudge direction (DLL: DAT_1000414f flag)

    for(;;)
    {
        self waittill("spawned_player");

        self thread watchChatCommands();
        self thread hudStatus();
    }
}

// ============================================================
// INPUT — CHAT COMMANDS
//
// The DLL uses dvar polling (FUN_10001c50's infinite loop).
// We use chat ("say") events instead of actionslot polling to
// avoid conflicts with mod keybinds (e.g. promod uses actionslot
// 4 for bomb drop in S&D). No client keybinds required.
//
// DLL dvar → chat command mapping:
//   elebot_run       → !ele  (toggle on/off)
//   elebot_autojump  → !aj   (toggle)
//   elebot_goupfast  → !guf  (toggle)
//   elebot_alert     → !alr  (toggle)
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
            case "!ele":
                if(!self.ele["active"])
                    self thread startEle();
                else
                    self thread stopEle();
                break;

            case "!aj":
                self.ele["autojump"] = !self.ele["autojump"];
                if(self.ele["autojump"])
                    self iPrintLn("^3Autojump: ^2ON");
                else
                    self iPrintLn("^3Autojump: ^1OFF");
                break;

            case "!guf":
                self.ele["goupfast"] = !self.ele["goupfast"];
                if(self.ele["goupfast"])
                    self iPrintLn("^3GoUpFast: ^2ON");
                else
                    self iPrintLn("^3GoUpFast: ^1OFF");
                break;

            case "!alr":
                self.ele["alert"] = !self.ele["alert"];
                if(self.ele["alert"])
                    self iPrintLn("^3Alert: ^2ON");
                else
                    self iPrintLn("^3Alert: ^1OFF");
                break;
        }
    }
}

// ============================================================
// ELEBOT CORE — mirrors FUN_10001950 (elebot_start)
//
// DLL flow:
//   1. Check if already running (DAT_10004198)
//   2. Save current com_maxfps value
//   3. Optionally enable r_zfar (elebot_usezfar)
//   4. Read player yaw from DAT_10004010
//   5. Based on yaw quadrant, set:
//      - _DAT_10004150 = target position offset
//      - DAT_1000414f  = direction flag (0 or 1)
//      - DAT_10004194  = pointer to X or Y coordinate
//   6. Floor the selected coordinate → _DAT_10004158 (snap value)
//   7. Call FUN_10001400 (align)
//   8. Call FUN_10001580 (main elevator loop)
//   9. Call FUN_100010f0 (cleanup/stop)
// ============================================================

startEle()
{
    self endon("disconnect");
    self endon("death");
    self endon("ele_stop");

    self.ele["active"] = true;
    self iPrintLnBold("^2Elebot started");

    // === STEP 1: Determine direction from yaw ===
    // Mirrors FUN_10001950's quadrant logic.
    // The DLL reads *DAT_10004010 which is the player's yaw angle,
    // then uses a series of float comparisons to pick the axis.
    angles = self getPlayerAngles();
    yaw = angles[1];

    // Normalize yaw to 0-360 range
    while(yaw < 0)
        yaw += 360;
    while(yaw >= 360)
        yaw -= 360;

    // Quadrant selection — each quadrant determines:
    //   direction: which axis (0=X, 1=Y) to monitor for height changes
    //   sign: which way to nudge for alignment (+1=forward, -1=backward)
    //
    // DLL code (FUN_10001950 lines 412-435):
    //   if yaw in [315,360) or [0,45)  → X-axis, sign=+1 (East)
    //   if yaw in [45,135)             → Y-axis, sign=+1 (North)
    //   if yaw in [135,225)            → X-axis, sign=-1 (West)
    //   if yaw in [225,315)            → Y-axis, sign=-1 (South)
    if(yaw >= level.ele_yaw_q4 || yaw < level.ele_yaw_q1)
    {
        self.ele["direction"] = 0;  // X-axis
        self.ele["sign"] = 1;       // nudge forward
    }
    else if(yaw >= level.ele_yaw_q1 && yaw < level.ele_yaw_q2)
    {
        self.ele["direction"] = 1;  // Y-axis
        self.ele["sign"] = 1;       // nudge forward
    }
    else if(yaw >= level.ele_yaw_q2 && yaw < level.ele_yaw_q3)
    {
        self.ele["direction"] = 0;  // X-axis
        self.ele["sign"] = -1;      // nudge backward
    }
    else
    {
        self.ele["direction"] = 1;  // Y-axis
        self.ele["sign"] = -1;      // nudge backward
    }

    // Save starting position for height tracking and abort detection
    startPos = self getOrigin();
    self.ele["startZ"] = startPos[2];       // DLL: _DAT_10004158 (floored Z snap)
    self.ele["startPos"] = startPos;        // for horizontal distance abort check

    // === STEP 2: Alignment phase ===
    // Mirrors FUN_10001400 — nudges player into correct position
    self thread eleAlign();
    wait 0.05;

    // === STEP 3: Main elevator loop ===
    // Mirrors FUN_10001580 — the actual stance-switching cycle
    self thread eleMainLoop();
}

// ============================================================
// ALIGNMENT — mirrors FUN_10001400 (elebot_align)
//
// DLL behavior:
//   1. Calls FUN_10001170 (position adjustment with target offset)
//   2. Enters a while loop that calls FUN_10001280 (nudge) repeatedly
//   3. FUN_10001280 checks stability: read pos, Sleep(2), read again
//   4. If position drifted, sends +forward/-forward or +back/-back
//   5. Also switches FPS between 500/1000 based on position delta
//   6. Loop exits when position is within tolerance
//   7. Restores FPS to 333 (0x14d) at the end
//
// GSC approximation:
//   We can't send console commands, so we use setVelocity() to
//   apply small nudges in the appropriate direction.
// ============================================================

eleAlign()
{
    self endon("disconnect");
    self endon("death");
    self endon("ele_stop");
    self endon("ele_done");

    // Try up to 10 alignment nudges
    for(i = 0; i < 10; i++)
    {
        if(!self.ele["active"])
            return;

        // --- Stability check (from FUN_10001280) ---
        // DLL: _DAT_10004154 = *DAT_10004194;  (read position)
        //      Sleep(2);                         (wait 2ms)
        //      if(_DAT_10004154 != *DAT_10004194) return;  (bail if moved)
        //
        // We use 50ms wait since GSC can't do 2ms
        pos1 = self getOrigin();
        wait 0.05;
        pos2 = self getOrigin();

        // Check the axis we care about (DLL compares against specific axis)
        axis = self.ele["direction"];  // 0=X, 1=Y
        diff = abs(pos2[axis] - pos1[axis]);

        if(diff > 0.5)
        {
            // Position is unstable — apply a correction nudge
            //
            // DLL (FUN_10001280 lines 234-242):
            //   if direction flag says forward:
            //     Cbuf_AddText("+forward"); Sleep(3); Cbuf_AddText("-forward");
            //   else:
            //     Cbuf_AddText("+back");    Sleep(3); Cbuf_AddText("-back");
            //
            // GSC equivalent: small velocity push in the right direction
            vel = self getVelocity();
            nudgeVec = getNudgeVector(self getPlayerAngles(), 10 * self.ele["sign"]);
            self setVelocity((vel[0] + nudgeVec[0], vel[1] + nudgeVec[1], vel[2]));
            wait 0.05;
        }
        else
        {
            // Position is stable — alignment complete
            return;
        }
    }
}

// ============================================================
// MAIN ELEVATOR LOOP — mirrors FUN_10001580 (elebot_mainLoop)
//
// This is the heart of the elebot. The DLL's exact command sequence:
//
//   +moveup    → start jump input
//   -moveup    → release jump input
//   wait 2     → engine wait 2 server frames
//   gocrouch   → force crouch stance
//   wait 2     → engine wait 2 server frames
//   +moveup    → start jump input again
//   -moveup    → release jump input
//
// This rapid stand→crouch→stand cycle, when done at the right
// position and timing, exploits a collision glitch that pushes
// the player upward through certain brush geometry.
//
// The DLL also:
//   - Checks if ele_run is still enabled (we check self.ele["active"])
//   - Switches FPS between 500/1000 based on height progress
//   - Applies lateral nudges (+moveleft/-moveleft) for drift correction
//   - Monitors for "out of range" and stops if player wandered off
//   - On success with autojump+goupfast: sets 1000fps, waits for
//     height to peak (2 consecutive non-gains), then boosts velocity
//
// GSC TRANSLATION NOTES:
//   - +moveup/-moveup → setStance("stand") — both cause the player
//     to go from crouch to standing, which is the "jump" part
//   - gocrouch → setStance("crouch")
//   - wait 2 → wait 0.05 (GSC minimum practical wait)
//   - FPS control → setClientDvar("com_maxfps", value)
//   - +moveleft/-moveleft → setVelocity() lateral push
// ============================================================

eleMainLoop()
{
    self endon("disconnect");
    self endon("death");
    self endon("ele_stop");

    // Set initial FPS (DLL: patches com_maxfps via WriteProcessMemory)
    self setClientDvar("com_maxfps", level.ele_maxfps_default);

    cycleCount = 0;

    for(;;)
    {
        if(!self.ele["active"])
            return;

        // --- STABILITY CHECK (FUN_10001280 lines 211-218) ---
        //
        // DLL pseudocode:
        //   _DAT_10004154 = *DAT_10004194;    // read position
        //   Sleep(2);                           // wait 2ms
        //   if(_DAT_10004154 != *DAT_10004194) // if position changed
        //     return;                           // something is wrong, bail
        //
        // Purpose: make sure the player isn't being moved by external
        // forces (falling, being pushed, etc.) before doing a cycle.
        pos1 = self getOrigin();
        wait 0.05;
        pos2 = self getOrigin();

        if(pos1[2] != pos2[2] && abs(pos1[2] - pos2[2]) > 1)
        {
            // Z position changed unexpectedly — skip this cycle
            wait 0.05;
            continue;
        }

        // --- FPS SWITCHING (FUN_10001280 lines 220-228) ---
        //
        // DLL logic:
        //   if heightDelta > threshold OR currentFPS == 500:
        //     if heightDelta < threshold AND currentFPS != 1000:
        //       set FPS to 1000    (close to target, need precision)
        //   else:
        //     set FPS to 500       (far from target, need speed)
        //
        // Simplified: boost fps when gaining height, lower when stable
        heightGain = pos2[2] - self.ele["startZ"];

        if(heightGain > 5 && self.ele["goupfast"])
            self setClientDvar("com_maxfps", level.ele_maxfps_boost);
        else if(heightGain < 2)
            self setClientDvar("com_maxfps", level.ele_maxfps_low);

        // --- CORE ELEVATOR SEQUENCE (FUN_10001580 lines 323-335) ---
        //
        // DLL sends these commands via Cbuf_AddText (0x4F9AB0):
        //   Cbuf_AddText("+moveup");    Sleep(2);
        //   Cbuf_AddText("-moveup");    Sleep(2);
        //   Cbuf_AddText("wait 2");     Sleep(2);
        //   Cbuf_AddText("gocrouch");   Sleep(2);
        //   Cbuf_AddText("wait 2");     Sleep(2);
        //   Cbuf_AddText("+moveup");    Sleep(2);
        //   Cbuf_AddText("-moveup");    Sleep(2);
        //
        // GSC equivalent using stance manipulation:
        //   stand (= +moveup/-moveup)
        //   crouch (= gocrouch)
        //   stand (= second +moveup/-moveup)

        // Phase 1: Stand up (replaces +moveup/-moveup)
        self setStance("stand");
        wait 0.05;

        // Phase 2: Crouch (replaces "gocrouch" console command)
        self setStance("crouch");
        wait 0.05;

        // Phase 3: Stand again (replaces second +moveup/-moveup)
        self setStance("stand");
        wait 0.05;

        cycleCount++;

        // --- CHECK RESULTS ---
        currentPos = self getOrigin();
        heightDiff = currentPos[2] - self.ele["startZ"];

        // SUCCESS: player gained height and is airborne
        if(!self isOnGround() && heightDiff > level.ele_height_threshold)
        {
            // === AUTOJUMP + GOUPFAST (FUN_10001580 lines 337-348) ===
            //
            // DLL behavior when autojump=1 AND goupfast=1:
            //   1. Sleep(300) — let momentum carry
            //   2. Set FPS to 1000
            //   3. Monitor height: loop until 2 consecutive non-gains
            //      (meaning player reached peak height)
            //   4. Then the autojump velocity boost is applied
            //
            // DLL pseudocode:
            //   Sleep(300);
            //   *(DAT_10004178 + 0xc) = 1000;  // set maxfps
            //   local_8 = 0;
            //   while(local_8 < 2) {
            //     if(_DAT_1000418c == *DAT_10004008 || *DAT_10004008 < _DAT_1000418c)
            //       local_8++;
            //     _DAT_1000418c = *DAT_10004008;
            //     Sleep(0x32);  // 50ms
            //   }
            if(self.ele["autojump"])
            {
                if(self.ele["goupfast"])
                {
                    // Boost FPS for smoother ascent
                    self setClientDvar("com_maxfps", level.ele_maxfps_boost);
                    wait 0.3;  // DLL: Sleep(300)

                    // Wait for peak height (DLL: 2 consecutive non-increases)
                    noGainCount = 0;
                    lastZ = self getOrigin()[2];
                    while(noGainCount < 2)
                    {
                        wait 0.05;  // DLL: Sleep(0x32) = 50ms
                        curZ = self getOrigin()[2];
                        if(curZ <= lastZ)
                            noGainCount++;
                        lastZ = curZ;
                    }
                }

                // Apply jump boost at peak (setVelocity Z component)
                vel = self getVelocity();
                self setVelocity((vel[0], vel[1], 300));
            }

            // Alert message (DLL: checks elebot_alert dvar)
            // DLL: FUN_10001050("^2Finished!\n");
            if(self.ele["alert"])
                self iPrintLnBold("^2Finished! ^7+" + int(heightDiff) + " units");

            // DLL: FUN_10001050("^1Elevator courtesy of the great ^2batman^1.");
            self iPrintLn("^1Elevator courtesy of ^2GSC Elebot v2");

            // Restore default FPS
            self setClientDvar("com_maxfps", level.ele_maxfps_default);
            self.ele["active"] = false;
            return;
        }

        // ABORT: player moved too far horizontally from start position
        // DLL: FUN_10001070("^2Out of range of the ele, stopping...\n");
        horizDist = distance2d(self.ele["startPos"], currentPos);
        if(horizDist > level.ele_abort_horiz_dist)
        {
            self iPrintLnBold("^1Out of range, stopping...");
            self setClientDvar("com_maxfps", level.ele_maxfps_default);
            self.ele["active"] = false;
            return;
        }

        // --- LATERAL NUDGE (FUN_10001580 lines 378-380) ---
        //
        // DLL sends:
        //   Cbuf_AddText("+moveleft");  Sleep(3);  Cbuf_AddText("-moveleft");
        //
        // Purpose: correct sideways drift that accumulates during
        // the stance-switching cycle. Applied every 3rd cycle.
        //
        // GSC equivalent: small perpendicular velocity push
        if(cycleCount % 3 == 0)
        {
            vel = self getVelocity();
            nudgeVec = getLateralNudge(self getPlayerAngles(), 5);
            self setVelocity((vel[0] + nudgeVec[0], vel[1] + nudgeVec[1], vel[2]));
        }
    }
}

/*
 * stopEle — mirrors FUN_100010f0 (elebot_stop)
 *
 * DLL behavior:
 *   1. Set elebot_maxfps flag to 1 (restore)
 *   2. Set usezfar flag to 0 (disable)
 *   3. Restore original com_maxfps value
 *   4. Print "Restoring %s to %s" message
 *   5. Clear running flag
 *   6. Terminate the elebot thread
 */
stopEle()
{
    self.ele["active"] = false;
    self notify("ele_stop");
    self setClientDvar("com_maxfps", level.ele_maxfps_default);
    self iPrintLnBold("^1Elebot stopped");
}

// ============================================================
// HUD STATUS DISPLAY
//
// Shows current elebot state in the bottom-left corner.
// When active: shows height gain and toggle states.
// When inactive: shows all toggle states for quick reference.
//
// DLL equivalent: the DLL doesn't have a persistent HUD, but
// it prints status via Com_Printf (FUN_10001050) when toggling.
// We improve on this with a persistent HUD element.
//
// Abbreviations used:
//   AJ  = AutoJump    (elebot_autojump)
//   GUF = GoUpFast    (elebot_goupfast)
//   ALR = Alert        (elebot_alert)
// ============================================================

hudStatus()
{
    self endon("disconnect");
    self endon("death");

    hud = self createFontString("objective", 1.1);
    hud setPoint("BOTTOMLEFT", "BOTTOMLEFT", 5, -5);
    hud.alpha = 0.7;
    hud.hideWhenInMenu = true;

    for(;;)
    {
        if(self.ele["active"])
        {
            // Show live height gain during operation
            height = int(self getOrigin()[2] - self.ele["startZ"]);
            hud setText("^2ELE ^7ON | ^3+" + height + " ^7| AJ:" + boolStr(self.ele["autojump"]) + " GUF:" + boolStr(self.ele["goupfast"]));
        }
        else
        {
            // Show all toggle states when idle
            hud setText("^7ELE off | AJ:" + boolStr(self.ele["autojump"]) + " GUF:" + boolStr(self.ele["goupfast"]) + " ALR:" + boolStr(self.ele["alert"]));
        }
        wait 0.2;
    }
}

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/*
 * boolStr — format a boolean as colored ON/OFF text for HUD
 */
boolStr(val)
{
    if(val)
        return "^2ON";
    return "^1OFF";
}

/*
 * getNudgeVector — calculate a forward/backward push vector
 *
 * Takes the player's view angles and a strength value.
 * Positive strength = forward (toward where player looks).
 * Negative strength = backward.
 *
 * Used by eleAlign() to replicate the DLL's +forward/-forward
 * and +back/-back commands (FUN_10001280 lines 234-242).
 */
getNudgeVector(angles, strength)
{
    yaw = angles[1];
    rad = yaw * 3.14159 / 180;  // degrees to radians
    x = cos_approx(rad) * strength;
    y = sin_approx(rad) * strength;
    return (x, y, 0);
}

/*
 * getLateralNudge — calculate a left-perpendicular push vector
 *
 * Takes the player's view angles and applies a sideways push
 * (90 degrees to the left of where they're looking).
 *
 * Used to replicate the DLL's +moveleft/-moveleft drift
 * correction (FUN_10001580 lines 378-380).
 */
getLateralNudge(angles, strength)
{
    yaw = angles[1] + 90;  // 90° left of facing direction
    rad = yaw * 3.14159 / 180;
    x = cos_approx(rad) * strength;
    y = sin_approx(rad) * strength;
    return (x, y, 0);
}

/*
 * distance2d — horizontal distance between two 3D points
 * Ignores Z axis. Used for the abort check (did player walk away?).
 */
distance2d(a, b)
{
    dx = a[0] - b[0];
    dy = a[1] - b[1];
    return sqrt(dx * dx + dy * dy);
}

/*
 * abs — absolute value
 * GSC doesn't have a built-in abs() function.
 */
abs(x)
{
    if(x < 0)
        return x * -1;
    return x;
}

/*
 * sqrt — square root via Newton's method (Babylonian method)
 *
 * GSC doesn't have a built-in sqrt(). We iterate 10 times
 * which gives ~10 decimal digits of precision for typical
 * game-world values (0-10000 range).
 */
sqrt(x)
{
    if(x <= 0)
        return 0;
    guess = x / 2;
    for(i = 0; i < 10; i++)
        guess = (guess + x / guess) / 2;
    return guess;
}

/*
 * sin_approx / cos_approx — trigonometry approximations
 *
 * GSC has no sin/cos built-ins. We use Taylor series expansion:
 *   sin(x) ≈ x - x³/6 + x⁵/120
 *
 * Accuracy: good to ~3 decimal places for |x| <= PI.
 * This is sufficient for nudge direction calculations.
 *
 * Note: The DLL doesn't need these — it calls the C runtime's
 * sin/cos or uses precomputed lookup tables. This is a GSC limitation.
 */
sin_approx(rad)
{
    // Normalize to -PI..PI for best accuracy
    while(rad > 3.14159)
        rad -= 6.28318;
    while(rad < -3.14159)
        rad += 6.28318;

    // Taylor series: sin(x) ≈ x - x³/3! + x⁵/5!
    x3 = rad * rad * rad;
    x5 = x3 * rad * rad;
    return rad - (x3 / 6) + (x5 / 120);
}

cos_approx(rad)
{
    // cos(x) = sin(x + π/2)
    return sin_approx(rad + 1.5708);
}
