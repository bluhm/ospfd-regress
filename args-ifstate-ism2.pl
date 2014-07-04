# test ospfd together with two interface state machines

use strict;
use warnings;
use Client;
use Default qw($area $hello_interval $tun_number $ospfd_ip $ospfd_rtrid);

our %tst_args = (
    ospfd => {
	conf => {
	    areas => {
		$area => {
		    "tun$tun_number:$ospfd_ip" => {
			'metric' => '15',
			'hello-interval' => $hello_interval,
			'router-dead-time' => '8',
			'router-priority' => '15',
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
	state => [
	    {
		pri => 1,
	    },
	    {
		pri => 2,
	    },
	],
	tasks => [
	    {
		name => "receive hello with dr 0.0.0.0 bdr 0.0.0.0, ".
		    "enter $ospfd_rtrid as our neighbor",
		check => {
		    dr  => "0.0.0.0",
		    bdr => "0.0.0.0",
		    nbrs => [],
		},
		state => [
		    {
			nbrs => [ $ospfd_rtrid, "10.188.0.19" ],
		    },
		    {
			nbrs => [ $ospfd_rtrid, "10.188.0.18" ],
		    },
		],
	    },
	    {
		name => "wait for neighbor 10.188.0.18 in received hello",
		check => {
		    dr  => "0.0.0.0",
		    bdr => "0.0.0.0",
		},
		wait => {
		    nbrs => [ "10.188.0.18", "10.188.0.19" ],
		},
		timeout => 5,  # 2 * hello interval + 1 second
	    },
	    {
		name => "we are 2-way, wait for dr $ospfd_ip and ".
		    "bdr 10.188.6.18 in received hello",
		check => {
		    nbrs => [ "10.188.0.18", "10.188.0.19" ],
		},
		wait => {
		    dr  => $ospfd_ip,
		    bdr => "10.188.6.19",
		},
		timeout => 11,  # dead interval + hello interval + 1 second
	    },
	],
    },
);

1;
