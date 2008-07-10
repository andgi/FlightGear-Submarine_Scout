###############################################################################
## $Id$
##
## Nasal for copilot view over the multiplayer network.
##
##  Copyright (C) 2007  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license.
##
###############################################################################

var p_lat     = "/position/latitude-deg";
var p_lon     = "/position/longitude-deg";
var p_alt     = "/position/altitude-ft";
var p_heading = "/orientation/heading-deg";
var p_pitch   = "/orientation/pitch-deg";
var p_roll    = "/orientation/roll-deg";
var r_lat     = "position/latitude-deg";
var r_lon     = "position/longitude-deg";
var r_alt     = "position/altitude-ft";
var r_heading = "orientation/true-heading-deg";
var r_pitch   = "orientation/pitch-deg";
var r_roll    = "orientation/roll-deg";

var move_player = func {
  var mpplayers =
    props.globals.getNode("/ai/models").getChildren("multiplayer");
  var r_callsign = getprop("/sim/remote/pilot-callsign");

  foreach (rplayer; mpplayers) {
    if ((rplayer.getChild("callsign") != nil) and
        (rplayer.getChild("callsign").getValue() == r_callsign)) {
      setprop(p_lat, rplayer.getNode(r_lat).getValue());
      setprop(p_lon, rplayer.getNode(r_lon).getValue());
      setprop(p_alt, rplayer.getNode(r_alt).getValue());

      setprop(p_heading, rplayer.getNode(r_heading).getValue());
      setprop(p_pitch,   rplayer.getNode(r_pitch).getValue());
      setprop(p_roll,    rplayer.getNode(r_roll).getValue());
 
      # Set the view paths.
      setprop("/sim/eye-lat-deg-path",
              rplayer.getNode(r_lat).getPath());
      setprop("/sim/eye-lon-deg-path",
              rplayer.getNode(r_lon).getPath());
      setprop("/sim/eye-alt-ft-path",
              rplayer.getNode(r_alt).getPath());

      setprop("/sim/eye-heading-deg-path",
              rplayer.getNode(r_heading).getPath());
      setprop("/sim/eye-pitch-deg-path",
              rplayer.getNode(r_pitch).getPath());
      setprop("/sim/eye-roll-deg-path",
              rplayer.getNode(r_roll).getPath());

      settimer(move_player, 0);
      return;
    }
  }
  # The tracked player is not around. Idle loop.
  settimer(move_player, 3.1415);
}

# Init.
setlistener("/sim/signals/fdm-initialized", func {
  move_player();
});
