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
use Tun 'opentun';

my $tun_device = $ENV{TUNDEV} ? "/dev/$ENV{TUNDEV}" : "/dev/tun5";
my $area_id = "10.188.0.0";
my $hello_interval = 2;
# Parameters for test client
my $t_mac_address = "2:3:4:5:6:7";
my $t_ospf_address = "10.188.6.18";
my $t_router_id = "10.188.6.18";
# Parameters for ospfd
my $o_router_id = $ENV{TUNIP} || "10.188.6.17";

my $check;
my $wait;
my $cv;

(my $tun_number = $tun_device) =~ s/\D*//;
my $tun = opentun($tun_number);

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
	after => 3,
	interval => $hello_interval,
	cb => sub {
	    my %ether = (
		src_str => $t_mac_address,
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
		neighbors_str                => [ "$o_router_id" ],
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

my $is = interface_state($t_router_id);

$handle->on_read(sub {
    my %ether = consume_ether(\$handle->{rbuf});
    if ($ether{type} == 0x0800) {
	handle_ip4();
    } elsif ($ether{type} == 0x0806) {
	handle_arp();
    } else {
	warn "ether type is not supported: $ether{type_hex}";
    }
});

sub handle_arp {
    my %arp = consume_arp(\$handle->{rbuf});
}

sub handle_ip4 {
    my %ip4 = consume_ip4(\$handle->{rbuf});
    unless ($ip4{p} == 89) {
	warn "ip4 proto is not ospf";
	return;
    }
    my %ospf = consume_ospf(\$handle->{rbuf});
    unless ($ospf{type} == 1) {
	warn "ospf type is not hello";
	return;
    }
    my %hello = consume_hello(\$handle->{rbuf});
    $handle->{rbuf} = "";  # just to be sure, packets must not cumulate

    my $compare = sub {
	my $expect = shift;
	if ($expect->{dr}) {
	    $hello{designated_router_str} eq $expect->{dr}
		or return "dr is $hello{designated_router_str}: ".
		    "expected $expect->{dr}";
	}
	if ($expect->{bdr}) {
	    $hello{backup_designated_router_str} eq $expect->{bdr}
		or return "bdr is $hello{backup_designated_router_str}: ".
		    "expected $expect->{bdr}";
	}
	if ($expect->{nbrs}) {
	    my @neighbors = sort @{$hello{neighbors_str} || []};
	    my @nbrs = @{$expect->{nbrs}};
	    "@neighbors" eq "@nbrs"
		or return "nbrs [@neighbors]: expected [@nbrs]";
	}
	return "";
    };

    my $error = $compare->($check);
    return $cv->croak("check: $error") if $error;
    print "check hello successful\n";

    my $reason;
    if ($wait) {
	$reason = $compare->($wait);
    }
    if ($reason) {
	print "wait for hello because of: $reason\n";
    } else {
	$cv->send();
    }
}

my @tasks = (
    {
	name => "hello mit dr bdr 0.0.0.0 empfangen, ".
	    "$t_router_id als neighbor eintragen",
	check => {
	    dr  => "0.0.0.0",
	    bdr => "0.0.0.0",
	    nbrs => [],
	},
	timeout => 3,  # hello interval + 1 second
	action => sub {
	    $is->{state}{nbrs} = [ "$t_router_id" ];
	},
    },
    {
	name => "auf neighbor $t_router_id warten",
	check => {
	    dr  => "0.0.0.0",
	    bdr => "0.0.0.0",
	},
	wait => {
	    nbrs => [ "$t_router_id" ],
	},
	timeout => 5,  # 2 * hello interval + 1 second
    },
    {
	name => "warten dass dr $o_router_id ist",
	check => {
	    nbrs => [ "$t_router_id" ],
	},
	wait => {
	    dr  => "$o_router_id",
	    bdr => "$t_router_id",
	},
	timeout => 11,  # dead interval + hello interval + 1 second
    },
);

$| = 1;

foreach my $task (@tasks) {
    print "Task: $task->{name}\n";
    $check = $task->{check};
    $wait = $task->{wait};
    my $timeout = $task->{timeout};
    my $t;
    if ($timeout) {
	$t = AnyEvent->timer(
	    after => $timeout,
	    cb => sub { $cv->croak("timeout after $timeout seconds"); },
	);
    }
    $cv = AnyEvent->condvar;
    $cv->recv;
    my $action = $task->{action};
    $action->() if $action;
}

print "Terminating\n"
