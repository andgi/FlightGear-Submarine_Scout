###############################################################################
##
## Submarine Scout class airship.
##
##  Copyright (C) 2007 - 2010  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license.
##
###############################################################################

var battery = nil;
var last_time = 0.0;
var ammeter_ave = 0.0;

setlistener("/sim/signals/fdm-initialized", func {
    battery = BatteryClass.new();
    setprop("/controls/electric/battery-switch", 1.0);
    setprop("/controls/electric/external-power", 0);
    setprop("/controls/electric/engine[0]/generator", 0);
    setprop("/controls/switches/inverter", 1);
    setprop("/controls/switches/nav-lights", 1);
    setprop("/controls/switches/beacon", 1);
    setprop("/controls/switches/strobe", 1);
    setprop("/controls/switches/cabin-lights", 1);
    print("Electrical System ... initialized");
    });


## The battery class is from the FGFS Aerostar (C) Syd Adams
var BatteryClass = {};

BatteryClass.new = func {
    var obj = { parents : [BatteryClass],
                ideal_volts : 24.0,
                ideal_amps : 30.0,
                amp_hours : 12.0,
                charge_percent : 1.0,
                charge_amps : 7.0 };
    return obj;
}

BatteryClass.apply_load = func( amps, dt ) {
    var amphrs_used = amps * dt / 3600.0;
    var percent_used = amphrs_used / me.amp_hours;
    me.charge_percent -= percent_used;
    if ( me.charge_percent < 0.0 ) {
        me.charge_percent = 0.0;
    } elsif ( me.charge_percent > 1.0 ) {
        me.charge_percent = 1.0;
    }
    return me.amp_hours * me.charge_percent;
}

BatteryClass.get_output_volts = func {
    var x = 1.0 - me.charge_percent;
    var tmp = -(3.0 * x - 1.0);
    var factor = (tmp*tmp*tmp*tmp*tmp + 32) / 32;
    return me.ideal_volts * factor;
}

BatteryClass.get_output_amps = func {
    var x = 1.0 - me.charge_percent;
    var tmp = -(3.0 * x - 1.0);
    var factor = (tmp*tmp*tmp*tmp*tmp + 32) / 32;
    return me.ideal_amps * factor;
}

###############################################################################

var update_virtual_bus = func( dt ) {
    var battery_volts = battery.get_output_volts();
    var external_volts = 0.0;
    var load = 0.0;

    var master_bat = getprop("/controls/electric/battery-switch");
    var external_switch = getprop("/controls/electric/external-power");
    var engine0_state = getprop("/engines/engine[0]/running");

    var bus_volts = 0.0;
    var power_source = nil;
    if ( master_bat ) {
        bus_volts = battery_volts;
        power_source = "battery";
    }

    var ammeter = 0.0;
    if ( bus_volts > 1.0 ) {
        load += 5.0;  # Why a constant load?

        if ( power_source == "battery" ) {
            ammeter = -load;
        } else {
            ammeter = battery.charge_amps;
        }
    }
    if ( power_source == "battery" ) {
        battery.apply_load( load, dt );
    } elsif ( bus_volts > battery_volts ) {
        battery.apply_load( -battery.charge_amps, dt );
    }

    ammeter_ave = 0.8 * ammeter_ave + 0.2 * ammeter;

    setprop("/systems/electrical/amps", ammeter_ave);
    setprop("/systems/electrical/volts", bus_volts);
    var vbus_volts = bus_volts;
    return load;
}

###############################################################################

var update_electrical = func {
    if(getprop("/sim/signals/fdm-initialized")){
	var time = getprop("/sim/time/elapsed-sec");
    	var dt = time - last_time;
    	last_time = time;
    	update_virtual_bus( dt );
    }

    settimer(update_electrical, 0);
}

setlistener("/sim/signals/fdm-initialized", func {
    settimer(update_electrical, 0);
    print("Electrical System ... running");
});
