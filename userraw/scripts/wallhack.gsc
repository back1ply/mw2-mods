init()
{
    level thread onPlayerConnect();
}

onPlayerConnect()
{
    for(;;)
    {
        level waittill("connected", player);
        player thread onPlayerSpawned();
    }
}

onPlayerSpawned()
{
    self endon("disconnect");
    for(;;)
    {
        self waittill("spawned_player");
        self thread wallhack_logic_func();
    }
}

wallhack_logic_func()
{
    self endon("disconnect");
    self endon("death");
    
    self notifyOnPlayerCommand("toggle_wallhack", "toggle_wallhack");
    setDvarIfUninitialized("toggle_wallhack", "Press to toggle Wallhack");

    if ( !isDefined( self.wallhack_enabled ) )
    {
        self.wallhack_enabled = 0;
    }

    for(;;)
    {
        self waittill("toggle_wallhack");
        
        if ( self.wallhack_enabled == 0 )
        {
            self ThermalVisionFOFOverlayOn();
            self iPrintLnBold("Wallhack ^2ON");
            self.wallhack_enabled = 1;
        }
        else
        {
            self ThermalVisionFOFOverlayOff();
            self iPrintLnBold("Wallhack ^1OFF");
            self.wallhack_enabled = 0;
        }
    }
}
