use strict;
use warnings;

our %args = (
    ospfd => {
	configtest => 0,
	conf => {
	    global => {
		'router-id' => '1.2.3.4',
	    },
	    areas => {
		'51.0.0.0' => {
		    "$ENV{TUNDEV}:$ENV{TUNIP}" => {
			'metric' => '15',
		    },
		},
	    },
	},
    },
);

1;
