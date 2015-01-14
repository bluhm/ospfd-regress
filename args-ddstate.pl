use strict;
use warnings;
use Default qw($ospfd_ip $ospfd_rtrid);

our %tst_args = (
    client => {
	tasks => [
	    {
		name => "receive hello with dr 0.0.0.0 bdr 0.0.0.0, ".
		    "enter $ospfd_rtrid as our neighbor",
		check => {
		    dr  => "0.0.0.0",
		    bdr => "0.0.0.0",
		    nbrs => [],
		},
		state => {
		    nbrs => [ $ospfd_rtrid ],
		},
	    },
	    {
		name => "Wait for dd from ospfd",
		wait => {
		    dd_bits => 7,
		},
		state => {
		    dd_bits => 7,
		},
		timeout => 10,  # XXX proper value
	    },
	],
    },
);

1;
