#!/usr/bin/perl

# Copyright (c) 2014 Alexander Bluhm <bluhm@openbsd.org>
# Copyright (c) 2014 Florian Riehm <mail@friehm.de>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use strict;
use warnings;
use Fcntl;
use Data::Dumper;
use YAML;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Strict;

use Packet;

my $tun_device = "/dev/tun6";
my $mac_address = "0:1:2:3:4:5";
my $ospf_address = "10.188.6.18";
my $router_id = "10.188.6.18";
my $area_id = "10.188.0.0";
my $hello_interval = 2;

my $cv = AnyEvent->condvar;

sysopen(my $tun, $tun_device, O_RDWR)
    or die "Open $tun_device failed: $!";

my $handle; $handle = AnyEvent::Handle->new(
    fh => $tun,
    read_size => 70000,  # little more then max ip size
    on_error => sub {
	$cv->croak("error on $tun_device: $!");
	$handle->destroy();
	undef $handle;
    },
    on_eof => sub {
	$cv->croak("end-of-file on $tun_device: $!");
	$handle->destroy();
	undef $handle;
    },
);

sub interface_state {
    my ($id) = @_;

    my %state = (
	dr  => "0.0.0.0",
	bdr => "0.0.0.0",
    );

    my $hello_count = 0;
    $state{timer} = AnyEvent->timer(
	after => 1,
	interval => $hello_interval,
	cb => sub {
	    my %ether = (
		src_str => $mac_address,
		dst_str => "01:00:5e:00:00:05",  # multicast ospf
		type    => 0x0800,               # ipv4
	    );
	    my %ip4 = (
		v       => 4,               # ipv4
		hlen    => 20,
		tos     => 0xc0,
		id      => $hello_count++,  # increment for debugging
		off     => 0,               # no fragment
		ttl     => 1,               # only for direct connected
		p       => 89,              # protocol ospf
		src_str => $id,             # use router id as address
		dst_str => "224.0.0.5",     # all ospf router multicast
	    );
	    my %ospf = (
		version       => 2,         # ospf v2
		type	      => 1,         # hello
		router_id_str => $id,
		area_id_str   => $area_id,
		autype        => 0,         # no authentication
	    );
	    my %hello = (
		network_mask_str             => "255.255.255.0",
		hellointerval                => $hello_interval,
		options                      => 0x02,
		rtr_pri		             => 1,
		routerdeadinterval           => 4 * $hello_interval,
		designated_router_str        => $state{dr},
		backup_designated_router_str => $state{bdr},
		neighbors_str                => [ "10.188.6.17" ],
	    );
	    $handle->push_write(
		construct_ether(\%ether,
		construct_ip4(\%ip4,
		construct_ospf(\%ospf,
		construct_hello(\%hello))))
	    );
	},
    );

    return \%state;
}

my %router_id2interface_state = (
    $router_id => interface_state($router_id),
);


$handle->on_read(sub {
    my %ether = consume_ether(\$handle->{rbuf});
    unless ($ether{type} == 0x0800) {
	warn "ether type is not ip4";
	return;
    }
    my %ip4 = consume_ip4(\$handle->{rbuf});
    unless ($ip4{p} == 89) {
	warn "ip4 proto is not ospf";
	return;
    }
    my %ospf = consume_ospf(\$handle->{rbuf});
    unless ($ospf{type} == 1) {
	warn "ospt type is not hello";
	return;
    }
    my %hello = consume_hello(\$handle->{rbuf});
    $handle->{rbuf} = "";  # just to be sure, packets must not cumulate

    foreach my $id (sort keys %router_id2interface_state) {
	my $is = $router_id2interface_state{$id};
	if (grep { $_ eq $id } @{$hello{neighbors_str}}) {
	    $is->{bdr} = "10.188.6.17";
	    print "see $id in hello of $ospf{router_id_str}\n";
	} else {
	    print "no $id in hello of $ospf{router_id_str}\n";
	}
    }
});

$cv->recv;

print "Terminating\n"

__END__

- pruefen, dass hello mit dr bdr 0.0.0.0 und keine neigbors
- hello mit dr bdr 0.0.0.0 senden, in als neighbor eintragen
- pruefen, dass hello mit dr bdr 0.0.0.0 und uns als neigbors
- warten bis WaitTimer abgelaufen ist
- pruefen dass dr 10.188.6.17 ist

@tasks = [
    {
	check => hello mit dr bdr 0.0.0.0 und keine neigbors
	action => hello mit dr bdr 0.0.0.0 senden, in als neighbor eintragen
    },
    {
	check => hello mit dr bdr 0.0.0.0
	wait => uns als neigbors
	action => warten bis WaitTimer abgelaufen ist
    },
    {
	check => pruefen dass bdr 0.0.0.0 und uns als neigbors
	wait => pruefen dass dr 10.188.6.17 ist
	action => Test Pass
    }
];

while (@tasks) {
    tasks[0]{check}() or die;
    if (!tasks[0]{wait} || tasks[0]{wait}()) {
	tasks[0]{action}();
	shift @task;
    }
}

