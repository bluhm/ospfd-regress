use strict;
use warnings;
use Client;

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
    client => {
	tasks => [
	    {
		name => "hello mit dr bdr 0.0.0.0 empfangen, ".
		    "10.188.6.18 als neighbor eintragen",
		check => {
		    dr  => "0.0.0.0",
		    bdr => "0.0.0.0",
		    nbrs => [],
		},
		action => sub {
		    my $is = Client::get_is();
		    $is->{state}{nbrs} = [ "10.188.6.18" ];
		},
	    },
	    {
		name => "auf neighbor 10.188.6.18 warten",
		check => {
		    dr  => "0.0.0.0",
		    bdr => "0.0.0.0",
		},
		wait => {
		    nbrs => [ "10.188.6.18" ],
		},
		timeout => 5,  # 2 * hello interval + 1 second
	    },
	    {
		name => "warten dass dr 10.188.6.17 ist",
		check => {
		    nbrs => [ "10.188.6.18" ],
		},
		wait => {
		    dr  => "10.188.6.17",
		    bdr => "10.188.6.18",
		},
		timeout => 11,  # dead interval + hello interval + 1 second
	    },
	],
    },
);

1;
