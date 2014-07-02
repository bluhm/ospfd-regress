use strict;
use warnings;

our %args = (
    ospfd => {
	configtest => 0,
	conf => {
	    global => {
		'router-id' => $ENV{TUNIP},
	    },
	    areas => {
		'10.188.0.0' => {
		    "$ENV{TUNDEV}:$ENV{TUNIP}" => {
			'metric' => '15',
			'hello-interval' => '2',
			'router-dead-time' => '8',
			'router-priority' => '15',
		    },
		},
	    },
	},
    },
    client => "interface.pl",
);

1;
