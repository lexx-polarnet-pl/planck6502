// karty są co 18mm
// pcb mają grubość 1.6mm

$karty = 6;

module pcb_holder() {
    difference() {
        cube([6,10,5]);
        // wyciecie na PCB 2.0mm
        //translate([2,-5,2]) cube([2,20,5]);
        // wyciecie na PCB 1.6mm
        translate([2.2,-5,2]) cube([1.6,20,5]);
        translate([3,15,7]) rotate([90,90,0]) cylinder(r=5,h=20,$fn=3);
    }
}

pcb_holder();

for ( i = [0 : $karty-1] ){
    translate([i*18, 0, 0])
    pcb_holder();
}

cube([($karty-1)*18+2,10,2]);