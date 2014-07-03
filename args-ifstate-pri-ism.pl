# test router priority with one interface state machine (ism)
# ospfd has prio 0, ism of the test has prio 1
# test that ism gets dr, there is no bdr

use strict;
use warnings;
use Client;

my $area = "10.188.0.0";
my $hello_interval = 2;
my $tun_device = $ENV{TUNDEV};
my $ospfd_ip = $ENV{TUNIP};

our %args = (
    ospfd => {
	configtest => 0,
	conf => {
	    global => {
		'router-id' => $ospfd_ip,
	    },
	    areas => {
		$area => {
		    "tun$tun_device:$ospfd_ip" => {
			'metric' => '15',
			'hello-interval' => $hello_interval,
			'router-dead-time' => '8',
			'router-priority' => '0',
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
	router_id => "10.188.6.18",
	tun_device => $tun_device,
	ospfd_ip => $ospfd_ip,
	state => {
	    pri => 1,
	},
	tasks => [
	    {
		name => "receive hello with dr 0.0.0.0 bdr 0.0.0.0, ".
		    "enter 10.188.6.18 as our neighbor",
		check => {
		    dr   => "0.0.0.0",
		    bdr  => "0.0.0.0",
		    nbrs => [],
		},
		state => {
		    nbrs => [ "10.188.6.17" ],
		},
	    },
	    {
		name => "wait for neighbor 10.188.6.18 in received hello",
		check => {
		    # XXX dr flipping between "0.0.0.0" and "10.188.6.18"
		    bdr => "0.0.0.0",
		},
		wait => {
		    nbrs => [ "10.188.6.18" ],
		},
		timeout => 5,  # 2 * hello interval + 1 second
	    },
	    {
		name => "we are 2-way, wait for dr $ospfd_ip and ".
		    "bdr 10.188.6.18 in received hello",
		check => {
		    nbrs => [ "10.188.6.18" ],
		},
		wait => {
		    dr => "10.188.6.18",
		    bdr  => "0.0.0.0",
		},
		timeout => 11,  # dead interval + hello interval + 1 second
	    },
	],
    },
);

1;
