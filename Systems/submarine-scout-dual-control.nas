###############################################################################
## $Id$
##
## Nasal module for dual control over the multiplayer network.
##
##  Copyright (C) 2008 - 2009  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license version 2 or later.
##
###############################################################################

# Renaming (almost :)
var DCT = dual_control_tools;

######################################################################
# Pilot/copilot aircraft identifiers. Used by dual_control.
var pilot_type   = "Aircraft/Submarine_Scout/Models/Submarine_Scout.xml";
var copilot_type = "Aircraft/Submarine_Scout/Models/Submarine_Scout-observer.xml";
var copilot_view = "W/T operator";

props.globals.initNode("/sim/remote/pilot-callsign", "", "STRING");

######################################################################
# MP enabled properties.
# NOTE: These must exist very early during startup - put them
#       in the -set.xml file.


######################################################################
# Useful local property paths.


###############################################################################
# Pilot MP property mappings and specific copilot connect/disconnect actions.

######################################################################
# Used by dual_control to set up the mappings for the pilot.
var pilot_connect_copilot = func (copilot) {

    return 
        [
         ######################################################################
         # Process received properties.
         ######################################################################

         ######################################################################
         # Process properties to send.
         ######################################################################
        ];
}

######################################################################
var pilot_disconnect_copilot = func {
    # Reset copilot controls. Slightly dangerous.
}


###############################################################################
# Copilot MP property mappings and specific pilot connect/disconnect actions.

######################################################################
# Used by dual_control to set up the mappings for the copilot.
var copilot_connect_pilot = func (pilot) {
    # Initialize Nasal wrappers for copilot pick animations.
    set_copilot_wrappers(pilot);

    return
        [
         ######################################################################
         # Process received properties.
         ######################################################################

         ######################################################################
         # Process properties to send.
         ######################################################################
        ];
}

######################################################################
var copilot_disconnect_pilot = func {

}

######################################################################
# Copilot Nasal wrappers

var set_copilot_wrappers = func (pilot) {
    # Set up aliases for the animations.
    pilot.getNode("sim/current-view/name", 1).
        setValue(getprop("sim/current-view/name"));
}
