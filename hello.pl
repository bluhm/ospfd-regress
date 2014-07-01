#!/usr/bin/perl

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
my $mac_address = "1:2:3:4:5:6";
my $ospf_address = "10.188.6.18";
my $router_id = "10.188.6.18";

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
    on_read => sub {
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

	$ether{src_str} = $mac_address;
	$ip4{src_str} = $ospf_address;
	$ospf{router_id_str} = $router_id;
	$hello{backup_designated_router_str} = $router_id;
	$hello{neighbors_str} = [ "10.188.6.17" ];
	$handle->push_write(
	    construct_ether(\%ether,
	    construct_ip4(\%ip4,
	    construct_ospf(\%ospf,
	    construct_hello(\%hello))))
	);
    },
);

$cv->recv;

print "Terminating\n"
