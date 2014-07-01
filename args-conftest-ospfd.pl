use strict;
use warnings;

# This test generates an ospfd.conf with a lot of config keys. Probably the
# config doesn't make sense, but ospfd -n should accept it as syntactically
# correct.

our %args = (
    ospfd => {
	configtest => 1,
	conf => {
	    global => {
		'fib-update' => 'no',
		'rdomain' => '4',
		'redistribute' => 'default',
		'rfc1583compat' => 'yes',
		'router-id' => '1.2.3.4',
		'rtlabel' => 'test external-tag 4',
		'spf-delay' => 'msec 2000',
		'spf-holdtime' => 'msec 4000',
		'stub router' => 'no',
	    },
	    areas => {
		'51.0.0.0' => {
		    'lo0:127.0.0.1' => {
			'metric' => '15',
			'auth-md 1' => 'yotVoo_Heypp',
			'auth-md-keyid' => '1',
			'auth-type' => 'crypt',
			'demote' => 'carp',
			'fast-hello-interval' => 'msec 300',
			'hello-interval' => '5',
			'metric' => '200',
			'retransmit-interval' => '7',
			'router-dead-time' => '4',
			'router-priority' => '24',
			'transmit-delay' => '3',
		    },
		},
	    },
	},
    },
);

1;
