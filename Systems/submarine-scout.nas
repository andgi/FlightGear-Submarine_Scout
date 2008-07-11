###############################################################################
## $Id$
##
## Submarine Scout airship
##
##  Copyright (C) 2007 - 2008  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license v2 or later.
##
###############################################################################

var static_trim_p = "/fdm/jsbsim/fcs/static-trim-cmd-norm";
var ballonet_valve_p =
    ["/fdm/jsbsim/buoyant_forces/gas-cell/ballonet[0]/valve_open",
     "/fdm/jsbsim/buoyant_forces/gas-cell/ballonet[1]/valve_open"];
var trim_ballast_p = "/fdm/jsbsim/inertia/pointmass-weight-lbs[3]";

###############################################################################
# For backwards compatibility.
var load_nasal = func (p, n) {
  if (contains(io, "load_nasal")) {
    io.load_nasal(p, n);
  } else {
    debug.load_nasal(p, n);
  }
}

###############################################################################
# User actions.
var weight_on_gear =
  props.globals.getNode("/fdm/jsbsim/forces/fbz-gear-lbs");
var ballast = "/fdm/jsbsim/inertia/pointmass-weight-lbs";

var print_wow = func {
  gui.popupTip("Current weight on gear " ~
               -weight_on_gear.getValue() ~ " lbs.");
}

var weighoff = func {
  gui.popupTip("Weigh-off to 10% in progress. " ~
               "Current weight " ~ -weight_on_gear.getValue() ~ " lbs.");
  var wow  = weight_on_gear.getValue();
  var cont = getprop(ballast);
  var new  = cont + 0.90 * wow;
  interpolate(ballast,
              (new > 0 ? new : 0.0),
              10);
}

var initial_weighoff = func {
    # Set initial static condition.
    var v = getprop("/fdm/jsbsim/static-condition/net-lift-lbs");
    setprop(trim_ballast_p,
            v > 0 ? 50.0 + v : 0);
    settimer(func {
        var v = getprop("/fdm/jsbsim/static-condition/net-lift-lbs");
        setprop(trim_ballast_p,
                v > 0 ? 50.0 + v : 0);
    }, 0.25);
}

setlistener("/sim/signals/fdm-initialized", func {
    initial_weighoff();
    setlistener("/sim/signals/reinit", func (reinit) {
        if (!reinit.getValue()) {
            setprop(static_trim_p, 0.65);
            initial_weighoff();
            settimer(func {
                ground_crew.place_ground_crew
                    (geo.aircraft_position(),
                     getprop("/orientation/heading-deg"));
                ground_crew.activate();
            }, 0.5);
        }
    });

    setprop(static_trim_p, 0.65);
    setprop(ballonet_valve_p[0], 0.10);
    setprop(ballonet_valve_p[1], 0.10);    
});

###############################################################################
# Initialize scenario network for full participation.
load_nasal(getprop("/sim/fg-root") ~
           "/Aircraft/Submarine_Scout/Systems/scenario-network.nas",
           "SubmarineScout");
scenario_network_init(1);

###############################################################################


###############################################################################
# Various
var loop = func {
    setprop("/fdm/jsbsim/fcs/sun-angle-rad",
            getprop("/sim/time/sun-angle-rad")); 
    settimer(loop, 3.14);
}

var init = func {
    aircraft.timer.new("/sim/time/hobbs/envelope", 73).start();
    
    settimer(loop, 3.14);
}

init();

###############################################################################
## Experimental armament.
var impact_signal =
    props.globals.getNode("sim/ai/aircraft/impact/bomb", 1);
var bomb =
    [props.globals.getNode("controls/armament/station[0]/present"),
     props.globals.getNode("controls/armament/station[1]/present")];
var trigger =
    [props.globals.getNode("/controls/armament/station[0]/release-all"),
     props.globals.getNode("/controls/armament/station[1]/release-all")];
var weight =
    [props.globals.getNode("/payload/weight[1]/weight-lb"),
     props.globals.getNode("/payload/weight[2]/weight-lb")];
var training_mode =
    props.globals.getNode("controls/armament/training-mode");
var selected = 0;

# Initialize armament.
bomb[0].setIntValue(1);
bomb[1].setIntValue(1);

var resolve_impact = func {
    print("Bomb impact!");
    var node = props.globals.getNode(cmdarg().getValue(), 1);
    var pos = geo.aircraft_position();
    pos.set_latlon(node.getNode("impact/latitude-deg").getValue(),
                   node.getNode("impact/longitude-deg").getValue(),
                   node.getNode("impact/elevation-m").getValue());
    broadcast.send(message_id["bomb_impact"] ~ Binary.encodeCoord(pos));
    geo.put_model("Aircraft/Submarine_Scout/Models/flare.osg",
                  pos.lat(), pos.lon(), pos.alt(),
                  node.getNode("impact/heading-deg").getValue(),
                  0, 0);
}

controls.trigger = func(b) {
    if (b and training_mode.getValue()) {
        trigger[selected].setValue(1);
        return;
    }
    if (b and bomb[selected].getValue()) {
        # Trigger pressed => drop bomb.
        trigger[selected].setValue(1);
        bomb[selected].setValue(0);
        weight[selected].setDoubleValue(0);
        return;
    }
    if (!b) {
        trigger[selected].setValue(0);
        selected = math.mod(selected + 1, 2);
        return;
    }
}

setlistener(impact_signal, resolve_impact);

###############################################################################
## Experimental ground party.

var ground_crew = {
    ##################################################
    init : func {
        me.UPDATE_INTERVAL = 0.42;
        me.loopid = 0;
        # There are two handling guy parties.
        me.position = geo.aircraft_position();
        me.pos = [geo.aircraft_position(), geo.aircraft_position()];
        me.connected =
            [props.globals.getNode
             ("/fdm/jsbsim/landing-party/wire-connected[0]"),
             props.globals.getNode
             ("/fdm/jsbsim/landing-party/wire-connected[1]")];
        me.wire_length =
            props.globals.getNode("/fdm/jsbsim/landing-party/wire-length-ft");
        me.model = {local : [nil, nil]};
        me.wind_heading =
            props.globals.getNode("/environment/wind-from-heading-deg");
        me.active = 0;

#        if (props.globals.getNode("/sim/presets/onground").getValue()) {
            me.active = 1;
            me.connected[0].setValue(0.99);
            me.connected[1].setValue(0.99);
#        }
        me.reset();
        print("Submarine Scout ground crew ... Standing by.");
    },
    ##################################################
    # Place the ground crew.
    place_ground_crew : func (pos, heading=nil, altitude=nil, name="local") {
        if (heading == nil) {
            me.heading = me.wind_heading.getValue();
        } else {
            me.heading = heading;
        }
        me.position = pos;
        me.pos[0].set(pos);
        me.pos[1].set(pos);
        me.pos[0].apply_course_distance(me.heading - 45.0, 20.0);
        me.pos[1].apply_course_distance(me.heading + 45.0, 20.0);
        if (altitude == nil) {
            me.pos[0].set_alt(geodinfo(me.pos[0].lat(), me.pos[0].lon())[0]);
            me.pos[1].set_alt(geodinfo(me.pos[1].lat(), me.pos[1].lon())[0]);
        } else {
            me.pos[0].set_alt(altitude);
            me.pos[1].set_alt(altitude);
        }  
        print("ground_crew: Handling parties at ");
        me.pos[0].dump(); me.pos[1].dump();

        setprop("/fdm/jsbsim/landing-party/latitude-deg[0]", me.pos[0].lat());
        setprop("/fdm/jsbsim/landing-party/longitude-deg[0]", me.pos[0].lon());
        setprop("/fdm/jsbsim/landing-party/altitude-ft[0]",
                me.pos[0].alt() * geo.M2FT);
        setprop("/fdm/jsbsim/landing-party/latitude-deg[1]", me.pos[1].lat());
        setprop("/fdm/jsbsim/landing-party/longitude-deg[1]", me.pos[1].lon());
        setprop("/fdm/jsbsim/landing-party/altitude-ft[1]",
                me.pos[1].alt() * geo.M2FT);
    
        if (me.model.local[0] != nil) me.model.local[0].remove();
        if (me.model.local[1] != nil) me.model.local[1].remove();
        me.model.local[0] = geo.put_model
            ("Aircraft/Submarine_Scout/Models/GroundCrew/wire-party.xml",
             me.pos[0], me.heading + 135.0);
        me.model.local[1] = geo.put_model
            ("Aircraft/Submarine_Scout/Models/GroundCrew/wire-party.xml",
             me.pos[1], me.heading - 135.0);
        broadcast.send(message_id["place_ground_crew"] ~
                       Binary.encodeCoord(me.pos[0]) ~
                       Binary.encodeCoord(me.pos[1]) ~
                       Binary.encodeDouble(me.heading));
    },
    ##################################################
    place_remote_ground_crew : func (key, pos1, pos2, heading) {
        if (!contains(me.model, key)) me.model[key] = [nil, nil];

        if (me.model[key][0] != nil) me.model[key][0].remove();
        if (me.model[key][1] != nil) me.model[key][1].remove();
        me.model[key][0] = geo.put_model
            ("Aircraft/Submarine_Scout/Models/GroundCrew/wire-party.xml",
             pos1, heading + 135.0);
        me.model[key][1] = geo.put_model
            ("Aircraft/Submarine_Scout/Models/GroundCrew/wire-party.xml",
             pos2, heading - 135.0);
    },
    ##################################################
    remove_remote_ground_crew : func (key) {
        if (!contains(me.model, key)) return;
        if (me.model[key][0] != nil) me.model[key][0].remove();
        if (me.model[key][1] != nil) me.model[key][1].remove();
    },
    ##################################################
    let_go : func {
        if (me.connected[0].getValue() or me.connected[1].getValue())
            me.announce("Handling guys released!");
        me.active = 0;
        me.connected[0].setValue(0.0);
        me.connected[1].setValue(0.0);
        me.wire_length.setValue(70.0);
    },
    ##################################################
    activate : func {
        me.active = 1;
        me.wire_length.setValue(70.0);
        me.place_ground_crew(me.position);
        me.announce("Ready for landing!");
    },
    ##################################################
    announce : func(msg) {
        setprop("/sim/messages/ground", msg);
    },
    ##################################################
    update : func {
        if (!me.active) return;
        
        if ((me.connected[0].getValue() < 1.0) and
            (getprop("/fdm/jsbsim/landing-party/total-distance-ft[0]") <
             2.0*getprop("/fdm/jsbsim/landing-party/wire-length-ft"))) {
            me.connected[0].setValue(1.0);
            me.announce("Left handling guy secured!");
        }
        if ((me.connected[1].getValue() < 1.0) and
            (getprop("/fdm/jsbsim/landing-party/total-distance-ft[1]") <
             2.0*getprop("/fdm/jsbsim/landing-party/wire-length-ft"))) {
            me.connected[1].setValue(1.0);
            me.announce("Right handling guy secured!");
        }
        if ((me.connected[0].getValue() >= 0.99) and
            (me.connected[1].getValue() >= 0.99) and
            (me.wire_length.getValue() == 70.0)) {
            interpolate(me.wire_length, 40.0, 30.0);
        }
    },
    ##################################################
    reset : func {
        me.loopid += 1;
        me._loop_(me.loopid);
    },
    ##################################################
    _loop_ : func(id) {
        id == me.loopid or return;
        me.update();
        settimer(func { me._loop_(id); }, me.UPDATE_INTERVAL);
    }
};

setlistener("/sim/signals/fdm-initialized", func {
    ground_crew.init();
    ground_crew.place_ground_crew(geo.aircraft_position(),
                                  getprop("/orientation/heading-deg"));

    setlistener("/sim/signals/click", func {
        var click_pos = geo.click_position();
        if (__kbd.alt.getBoolValue()) {
            SubmarineScout.ground_crew.place_ground_crew(click_pos,
                                                         nil,
                                                         click_pos.alt());
        }
    });
});

###############################################################################
## Experimental ALDIS lamp.

var ALDIS_lamp = {
    ##################################################
    init : func {
        me.UPDATE_INTERVAL = 0.0;
        me.loopid = 0;
        me.active = 0;
        me.source_view = view.indexof("W/T operator");
        me.stoved = { heading : 320.0,
                      pitch   : -45.0 ,
                      offset  : [0.0, 0.0, 0.0]
                    };
        me.heading =
            props.globals.getNode("sim/multiplay/generic/float[1]");
        me.pitch =
            props.globals.getNode("sim/multiplay/generic/float[2]");
        me.trigger = props.globals.getNode("sim/multiplay/generic/int[2]");
        me.location = props.globals.getNode("instrumentation/aldis/", 1);
        var src = props.globals.getNode("sim/view[100]/config");
        me.offset = [src.getNode("z-offset-m").getValue(),
                     src.getNode("x-offset-m").getValue(),
                     src.getNode("y-offset-m").getValue()];
        me.reset(0);
        print("ALDIS lamp ... initialized");
    },
    ##################################################
    update : func {
        if (view.index == me.source_view) {
            var src = props.globals.getNode("sim/current-view");
            me.heading.setValue(src.getNode("heading-offset-deg").getValue());
            me.pitch.setValue(src.getNode("pitch-offset-deg").getValue());
            me.location.getNode("x-offset-m").
                setValue(src.getNode("z-offset-m").getValue() - me.offset[0]);
            me.location.getNode("y-offset-m").
                setValue(src.getNode("x-offset-m").getValue() - me.offset[1]);
            me.location.getNode("z-offset-m").
                setValue(src.getNode("y-offset-m").getValue() - me.offset[2]);
        }
    },
    ##################################################
    reset : func (b = 0) {
        me.loopid += 1;
        me.location.getNode("x-offset-m", 1).setValue(me.stoved.offset[0]);
        me.location.getNode("y-offset-m", 1).setValue(me.stoved.offset[1]);
        me.location.getNode("z-offset-m", 1).setValue(me.stoved.offset[2]);
        me.heading.setValue(me.stoved.heading);
        me.pitch.setValue(me.stoved.pitch);
        me.active = b;
        if (b) me._loop_(me.loopid);
    },
    ##################################################
    _loop_ : func(id) {
        id == me.loopid or return;
        me.update();
        settimer(func { me._loop_(id); }, me.UPDATE_INTERVAL);
    }
};

# Override controls.trigger().
var old_controls_trigger = controls.trigger;
controls.trigger = func(b) {
    if (b) {
        if (view.index != 0) {
            if (ALDIS_lamp.active) ALDIS_lamp.trigger.setValue(b);
        } else {
            old_controls_trigger(b);
        }
    } else {
        old_controls_trigger(b);
        ALDIS_lamp.trigger.setValue(b);
    }
}

setlistener("/sim/signals/fdm-initialized", func {
    ALDIS_lamp.init();
});
