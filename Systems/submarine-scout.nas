###############################################################################
##
## Submarine Scout airship
##
##  Copyright (C) 2007 - 2015  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license v2 or later.
##
###############################################################################

var gas_valve_p = "/fdm/jsbsim/fcs/gas-valve-cmd-norm";
var ballonet_outflow_valve_p =
    ["/fdm/jsbsim/fcs/ballonet-out-valve-cmd-norm[0]",
     "/fdm/jsbsim/fcs/ballonet-out-valve-cmd-norm[1]"];
var ballonet_inflow_valve_p =
    ["/fdm/jsbsim/fcs/ballonet-in-valve-cmd-norm[0]",
     "/fdm/jsbsim/fcs/ballonet-in-valve-cmd-norm[1]"];
var rip_cord_p = "/fdm/jsbsim/fcs/rip-cord-cmd-norm";
var ballast_p = "/fdm/jsbsim/inertia/pointmass-weight-lbs[0]";

###############################################################################
# User actions.
var weight_on_gear =
  props.globals.getNode("/fdm/jsbsim/forces/fbz-gear-lbs");

var print_wow = func {
  gui.popupTip("Current weight on gear " ~
               -weight_on_gear.getValue() ~ " lbs.");
}

var auto_weighoff = func {
    var lift = getprop("/fdm/jsbsim/static-condition/net-lift-lbs");
    var v = getprop(ballast_p) + 50 + lift;
        
    print("Submarine Scout: Auto weigh off from " ~ (-lift) ~
          " lb heavy to 50 lb heavy.");

    interpolate(ballast_p,
                (v > 0 ? v : 0),
                0.5);
}


var initial_weighoff = func {
    # Set initial static condition.
    # Finding the right static condition at initialization time is tricky.
    auto_weighoff();
    settimer(auto_weighoff, 0.25);
    settimer(auto_weighoff, 1.0);
    # Fill up the envelope if not at pressure already. A bit of a hack.
    settimer(func {
        setprop("/fdm/jsbsim/buoyant_forces/gas-cell/contents-mol",
                2.0 *
                getprop("/fdm/jsbsim/buoyant_forces/gas-cell/contents-mol"));
    }, 0.8);
}

var drop_ballast = func(v) {
    var new = getprop(SubmarineScout.ballast_p) - v;
    interpolate(SubmarineScout.ballast_p,
                (new > 0.0 ? new : 0.0), 0.5);
}

setlistener("/sim/signals/fdm-initialized", func {
    initial_weighoff();
    setlistener("/sim/signals/reinit", func (reinit) {
        if (!reinit.getValue()) {
            initial_weighoff();
            settimer(func {
                ground_crew.place_ground_crew
                    (geo.aircraft_position(),
                     getprop("/orientation/heading-deg"));
                ground_crew.activate();
            }, 0.5);
        }
    });

    setprop(ballonet_outflow_valve_p[0], 0.0);
    setprop(ballonet_outflow_valve_p[1], 0.0);    
    setprop(ballonet_inflow_valve_p[0], 1.0);
    setprop(ballonet_inflow_valve_p[1], 1.0);

    # Disable the autopilot menu.
    gui.menuEnable("autopilot", 0);
});

###############################################################################
# Initialize scenario network for full participation.
io.load_nasal(getprop("/sim/aircraft-dir") ~ "/Systems/scenario-network.nas",
              "SubmarineScout");
scenario_network_init(1);

###############################################################################


###############################################################################
# Various
var loop = func {
    setprop("/fdm/jsbsim/environment/sun-angle-rad",
            getprop("/sim/time/sun-angle-rad")); 
    settimer(loop, 3.14);
}

var init = func {
    aircraft.timer.new("/sim/time/hobbs/envelope", 73).start();
    
    settimer(loop, 3.14);
}

init();

###############################################################################
## Armament.
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

var resolve_impact = func (n) {
    print("Bomb impact!");
    var node = props.globals.getNode(n.getValue(), 1);
    var pos = geo.Coord.new().set_latlon
                  (node.getNode("impact/latitude-deg").getValue(),
                   node.getNode("impact/longitude-deg").getValue(),
                   node.getNode("impact/elevation-m").getValue());
    broadcast.send(message_id["bomb_impact"] ~ Binary.encodeCoord(pos));
# FIXME: Need a new model.
#    geo.put_model(getprop("/sim/aircraft-dir") ~ "/Models/flare.osg",
#                  pos.lat(), pos.lon(), pos.alt(),
#                  node.getNode("impact/heading-deg").getValue(),
#                  0, 0);
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
## Ground party.

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
                me.pos[0].alt() * M2FT);
        setprop("/fdm/jsbsim/landing-party/latitude-deg[1]", me.pos[1].lat());
        setprop("/fdm/jsbsim/landing-party/longitude-deg[1]", me.pos[1].lon());
        setprop("/fdm/jsbsim/landing-party/altitude-ft[1]",
                me.pos[1].alt() * M2FT);
    
        if (me.model.local[0] != nil) me.model.local[0].remove();
        if (me.model.local[1] != nil) me.model.local[1].remove();
        me.model.local[0] = geo.put_model
            (getprop("/sim/aircraft-dir") ~ "/Models/GroundCrew/wire-party.xml",
             me.pos[0], me.heading + 135.0);
        me.model.local[1] = geo.put_model
            (getprop("/sim/aircraft-dir") ~ "/Models/GroundCrew/wire-party.xml",
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
            (getprop("/sim/aircraft-dir") ~ "/Models/GroundCrew/wire-party.xml",
             pos1, heading + 135.0);
        me.model[key][1] = geo.put_model
            (getprop("/sim/aircraft-dir") ~ "/Models/GroundCrew/wire-party.xml",
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
## ALDIS lamp.

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

###############################################################################
# About dialog.

var ABOUT_DLG = 0;

var dialog = {
#################################################################
    init : func (x = nil, y = nil) {
        me.x = x;
        me.y = y;
        me.bg = [0, 0, 0, 0.3];    # background color
        me.fg = [[1.0, 1.0, 1.0, 1.0]]; 
        #
        # "private"
        me.title = "About";
        me.dialog = nil;
        me.namenode = props.Node.new({"dialog-name" : me.title });
    },
#################################################################
    create : func {
        if (me.dialog != nil)
            me.close();

        me.dialog = gui.Widget.new();
        me.dialog.set("name", me.title);
        if (me.x != nil)
            me.dialog.set("x", me.x);
        if (me.y != nil)
            me.dialog.set("y", me.y);

        me.dialog.set("layout", "vbox");
        me.dialog.set("default-padding", 0);

        var titlebar = me.dialog.addChild("group");
        titlebar.set("layout", "hbox");
        titlebar.addChild("empty").set("stretch", 1);
        titlebar.addChild("text").set
            ("label",
             "About");
        var w = titlebar.addChild("button");
        w.set("pref-width", 16);
        w.set("pref-height", 16);
        w.set("legend", "");
        w.set("default", 0);
        w.set("key", "esc");
        w.setBinding("nasal", "SubmarineScout.dialog.destroy(); ");
        w.setBinding("dialog-close");
        me.dialog.addChild("hrule");

        var content = me.dialog.addChild("group");
        content.set("layout", "vbox");
        content.set("halign", "center");
        content.set("default-padding", 5);
        props.globals.initNode("sim/about/text",
             "Royal Naval Air Service Submarine Scout Zero airship for FlightGear\n" ~
             "Copyright (C) 2007 - 2015  Anders Gidenstam\n\n" ~
             "FlightGear flight simulator\n" ~
             "Copyright (C) 1996 - 2015  http://www.flightgear.org\n\n" ~
             "This is free software, and you are welcome to\n" ~
             "redistribute it under certain conditions.\n" ~
             "See the GNU GENERAL PUBLIC LICENSE Version 2 for the details.",
             "STRING");
        var text = content.addChild("textbox");
        text.set("halign", "fill");
        #text.set("slider", 20);
        text.set("pref-width", 400);
        text.set("pref-height", 300);
        text.set("editable", 0);
        text.set("property", "sim/about/text");

        #me.dialog.addChild("hrule");

        fgcommand("dialog-new", me.dialog.prop());
        fgcommand("dialog-show", me.namenode);
    },
#################################################################
    close : func {
        fgcommand("dialog-close", me.namenode);
    },
#################################################################
    destroy : func {
        ABOUT_DLG = 0;
        me.close();
        delete(gui.dialog, "\"" ~ me.title ~ "\"");
    },
#################################################################
    show : func {
        if (!ABOUT_DLG) {
            ABOUT_DLG = 1;
            me.init(400, getprop("/sim/startup/ysize") - 500);
            me.create();
        }
    }
};
###############################################################################

# Popup the about dialog.
var about = func {
    dialog.show();
}
