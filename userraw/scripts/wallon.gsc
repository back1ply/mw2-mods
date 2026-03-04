/*
 *	Standalone Wallhack Script
 *	Usage: This script is intended to be loaded independently.
 *	Command: /mvm_wallon (Binds 'mvm_wallon' to toggle cg_drawThroughWalls)
 */

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
        self thread wallon_logic();
    }
}

wallon_logic()
{
    self endon("disconnect");
    self endon("death");
    
    // Set default state
    if (!isDefined(self.wallon_state))
        self.wallon_state = 0;

    self notifyOnPlayerCommand("mvm_wallon", "mvm_wallon");
    
    for(;;)
    {
        self waittill("mvm_wallon");
        
        if (self.wallon_state == 0)
        {
            self setClientDvar("cg_drawThroughWalls", 1);
            self.wallon_state = 1;
            self iPrintLn("Wallhack: ^2ON");
        }
        else
        {
            self setClientDvar("cg_drawThroughWalls", 0);
            self.wallon_state = 0;
            self iPrintLn("Wallhack: ^1OFF");
        }
    }
}
