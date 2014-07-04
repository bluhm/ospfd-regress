# test ospfd without any interface state machines
# the ospfd will get dr and there must be no neighbors

use strict;
use warnings;
use Client;
use Defaults '$area';

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
	state => [],
	tasks => [
	    {
		name => "receive hello with dr 0.0.0.0 bdr 0.0.0.0",
		check => {
		    dr  => "0.0.0.0",
		    bdr => "0.0.0.0",
		    nbrs => [],
		},
	    },
	    {
		name => "there must be no nbrs, wait until dr $ospfd_ip",
		check => {
		    bdr => "0.0.0.0",
		    nbrs => [],
		},
		wait => {
		    dr => $ospfd_ip,
		},
		timeout => 11,  # dead interval + hello interval + 1 second
	    },
	],
    },
);

1;
