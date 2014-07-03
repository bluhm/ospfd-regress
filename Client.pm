# Copyright (c) 2010-2014 Alexander Bluhm <bluhm@openbsd.org>
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

package Client;
use parent 'Proc';
use Carp;

use Fcntl;
use Data::Dumper;
use YAML;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Strict;

use Packet;
use Tun 'opentun';

my $tun_device = $ENV{TUNDEV} ? "/dev/$ENV{TUNDEV}" : "/dev/tun5";
my $area_id;
my $hello_interval;
# Parameters for test client
my $c_mac_address;
my $c_ospf_address;
my $c_router_id;
# Parameters for ospfd
my $o_router_id = $ENV{TUNIP} || "10.188.6.17";

my $handle; 
my $check;
my $wait;
my $cv;
my $is;

sub handle_arp {
    my %arp = consume_arp(\$handle->{rbuf});
    my %ether = (
	src_str => $c_mac_address,
	dst_str => $arp{sha_str},
	type    => 0x0806,
    );
    $arp{op} = 2;
    @arp{qw(sha_str spa_str tha_str tpa_str)} =
	($c_mac_address, @arp{qw(tpa_str sha_str spa_str)});
    $handle->push_write(
	construct_ether(\%ether,
	construct_arp(\%arp))
    );
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

sub get_is {
    return $is;
}

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
		src_str => $c_mac_address,
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

sub runtest {
    my $self = shift;
    my @tasks = @{$self->{tasks}};

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
}

sub new {
    my ($class, %args) = @_;
    $args{logfile} ||= "client.log";
    $args{up} = "Starting test client";
    $args{down} = "Terminating";
    $args{func} = \&runtest;
    my $self = Proc::new($class, %args);
    return $self;
}

sub child {
    my $self = shift;

    $area_id = $self->{area} or die "area id missing";
    $hello_interval = $self->{hello_intervall}
	or die "hello_interval missing";
    $c_mac_address = $self->{mac_address}
	or die "client mac address missing";
    $c_ospf_address = $self->{ospf_address}
	or die "client ospf address missing";
    $c_router_id = $self->{router_id}
	or die "client router id missing";

    (my $tun_number = $tun_device) =~ s/\D*//;
    my $tun = opentun($tun_number);

    $handle = AnyEvent::Handle->new(
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
	on_read => sub {
	    my %ether = consume_ether(\$handle->{rbuf});
	    if ($ether{type} == 0x0800) {
		handle_ip4(\$handle->{rbuf});
	    } elsif ($ether{type} == 0x0806) {
		handle_arp(\$handle->{rbuf});
	    } else {
		warn "ether type is not supported: $ether{type_hex}";
	    }
	    $handle->{rbuf} = "";  # packets must not cumulate
	},
    );

    $is = interface_state($c_router_id);
}

1;
