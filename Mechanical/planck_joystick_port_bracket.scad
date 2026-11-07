// joy port shape
module joy_port_shape() {
    translate([-7,0,0]) cube([14,24,10]);
    translate([-9,0,0]) cube([18,10,11]);
    translate([-11,3,0]) cube([22,2.5,11]);
}

module screw_with_nut_cut() {
    translate([0,15,-5]) cylinder(r=1.6,h=20, $fn=20);
    #translate([0,15,11]) rotate([0,0,90]) cylinder(r=3,h=5, $fn=6);
}


difference() {
    translate([-24,0,0]) cube([48,20,13]);
    translate([24/2,0,0]) joy_port_shape();
    translate([-24/2,0,0]) joy_port_shape();
    screw_with_nut_cut();
    translate([-21.5,0,0]) screw_with_nut_cut();
    translate([21.5,0,0]) screw_with_nut_cut();
}

    