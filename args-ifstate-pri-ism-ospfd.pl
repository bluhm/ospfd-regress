# test router priority with one interface state machine (ism)
# ospfd has prio 1, ism of the test has prio 2
# test that ospfd gets bdr (does not work), ism gets dr

use strict;
use warnings;
use Client;
use Default '$area';

my $hello_interval = 2;
my $tun_number = $ENV{TUNDEV};
my $ospfd_ip = $ENV{TUNIP};
my $ospfd_rtrid = $ENV{RTRID};

our %tst_args = (
    ospfd => {
	configtest => 0,
	conf => {
	    global => {
		'router-id' => $ospfd_rtrid,
	    },
	    areas => {
		$area => {
		    "tun$tun_number:$ospfd_ip" => {
			'metric' => '15',
			'hello-interval' => $hello_interval,
			'router-dead-time' => '8',
			'router-priority' => '1',
		    },
		},
	    },
	},
    },
    client => {
	area => $area,
	hello_intervall => $hello_interval,
	mac_address => "2:3:4:5:6:7",
	ospf_address => "10.188.6.18",
	router_id => "10.188.0.18",
	tun_number => $tun_number,
	ospfd_ip => $ospfd_ip,
	ospfd_rtrid => $ospfd_rtrid,
	state => {
	    pri => 2,
	},
	tasks => [
	    {
		name => "receive hello with dr 0.0.0.0 bdr 0.0.0.0, ".
		    "enter $ospfd_rtrid as our neighbor",
		check => {
		    dr   => "0.0.0.0",
		    bdr  => "0.0.0.0",
		    nbrs => [],
		},
		state => {
		    nbrs => [ $ospfd_rtrid ],
		},
	    },
	    {
		name => "wait for neighbor 10.188.0.18 in received hello",
		check => {
		    dr  => "0.0.0.0",
		    bdr => "0.0.0.0",
		},
		wait => {
		    nbrs => [ "10.188.0.18" ],
		},
		timeout => 5,  # 2 * hello interval + 1 second
	    },
	    {
		name => "we are 2-way, wait for dr 10.188.6.18 and ".
		    "bdr $ospfd_ip in received hello",
		check => {
		    nbrs => [ "10.188.0.18" ],
		},
		wait => {
		    dr => "10.188.6.18",
		    bdr  => "0.0.0.0"  # XXX should be $ospfd_ip
		},
		timeout => 11,  # dead interval + hello interval + 1 second
	    },
	],
    },
);

1;
