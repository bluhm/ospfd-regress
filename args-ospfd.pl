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
		    'lo0:127.0.0.1' => {
			'metric' => '15',
		    },
		},
	    },
	},
    },
);

1;
