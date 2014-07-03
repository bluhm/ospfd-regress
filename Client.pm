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

my $tun_device;
my $area;
my $hello_interval;
# Parameters for interface state machine of the test
my $ism_mac;
my $ism_ip;
my $ism_rtrid;
# Parameters for ospfd under test
my $ospfd_ip;
my $ospfd_rtrid;

my $handle; 
my $check;
my $wait;
my $cv;
my $ism;

sub handle_arp {
    my %arp = consume_arp(\$handle->{rbuf});
    my %ether = (
	src_str => $ism_mac,
	dst_str => $arp{sha_str},
	type    => 0x0806,
    );
    $arp{op} = 2;
    @arp{qw(sha_str spa_str tha_str tpa_str)} =
	($ism_mac, @arp{qw(tpa_str sha_str spa_str)});
    $handle->push_write(
	construct_ether(\%ether,
	construct_arp(\%arp))
    );
}

sub handle_ip {
    my %ip = consume_ip(\$handle->{rbuf});
    unless ($ip{p} == 89) {
	warn "ip proto is not ospf";
	return;
    }
    my %ospf = consume_ospf(\$handle->{rbuf});
    $ospf{router_id_str} eq $ospfd_rtrid
	or return "ospfd rtrid is $ospf{router_id_str}: expected $$ospfd_rtrid";
    $ospf{area_id_str} eq $area
	or return "ospfd area is $ospf{area_id_str}: expected $area";
    if ($ospf{type} == 1) {
	handle_hello();
    } else {
	warn "ospf type is not supported: $ospf{type}";
    }
}

sub handle_hello {
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

sub interface_state_machine {
    my ($id) = @_;

    my %state = (
	dr  => "0.0.0.0",
	bdr => "0.0.0.0",
	pri => 1,
    );

    my $hello_count = 0;
    $state{timer} = AnyEvent->timer(
	after => 3,
	interval => $hello_interval,
	cb => sub {
	    my %ether = (
		src_str => $ism_mac,
		dst_str => "01:00:5e:00:00:05",  # multicast ospf
		type    => 0x0800,               # ipv4
	    );
	    my %ip = (
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
		area_id_str   => $area,
		autype        => 0,         # no authentication
	    );
	    my %hello = (
		network_mask_str             => "255.255.255.0",
		hellointerval                => $hello_interval,
		options                      => 0x02,
		rtr_pri		             => $state{pri},
		routerdeadinterval           => 4 * $hello_interval,
		designated_router_str        => $state{dr},
		backup_designated_router_str => $state{bdr},
		neighbors_str                => $state{nbrs},
	    );
	    $handle->push_write(
		construct_ether(\%ether,
		construct_ip(\%ip,
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

    my $state = $self->{state};
    %$ism = (%$ism, %$state) if $state;

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
	$state = $task->{state};
	%$ism = (%$ism, %$state) if $state;
    }

    print "Terminating\n";
    sleep 1;
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

    $area = $self->{area} or die "area id missing";
    $hello_interval = $self->{hello_intervall}
	or die "hello_interval missing";
    $ism_mac = $self->{mac_address}
	or die "client mac address missing";
    $ism_ip = $self->{ospf_address}
	or die "client ospf address missing";
    $ism_rtrid = $self->{router_id}
	or die "client router id missing";
    $tun_device =  $self->{tun_device}
	or die "tun device missing";
    # XXX split ip and rtrid
    $ospfd_ip = $ospfd_rtrid = $self->{ospfd_ip}
	or die "ospfd ip missing";

    my $tun = opentun($tun_device);

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
		handle_ip();
	    } elsif ($ether{type} == 0x0806) {
		handle_arp();
	    } else {
		warn "ether type is not supported: $ether{type_hex}";
	    }
	    $handle->{rbuf} = "";  # packets must not cumulate
	},
    );

    $ism = interface_state_machine($ism_rtrid);
}

1;
