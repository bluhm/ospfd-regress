#!/usr/bin/perl

use strict;
use warnings;
use Fcntl;
use Data::Dumper;
use YAML;

use Packet;

my $tun_device = 6;
my $mac_address = "1:2:3:4:5:6";
my $ospf_address = "10.188.6.18";
my $router_id = "10.188.6.18";

sysopen(my $tun, "/dev/tun$tun_device", O_RDWR)
    or die "Open /dev/tun$tun_device failed: $!";

for (;;) {
    my $n = sysread($tun, my $packet, 70000);
    defined($n) or die "sysread failed: $!";
    $n or last;
    print "Read $n bytes\n";

    my %ether = consume_ether(\$packet);
    unless ($ether{type} == 0x0800) {
	warn "ether type is not ip4";
	next;
    }
    my %ip4 = consume_ip4(\$packet);
    unless ($ip4{p} == 89) {
	warn "ip4 proto is not ospf";
	next;
    }
    my %ospf = consume_ospf(\$packet);
    unless ($ospf{type} == 1) {
	warn "ospt type is not hello";
	next;
    }
    my %hello = consume_hello(\$packet);

    $ether{src_str} = $mac_address;
    $ip4{src_str} = $ospf_address;
    $ospf{router_id_str} = $router_id;
    $hello{backup_designated_router_str} = $router_id;
    $hello{neighbors_str} = [ "10.188.6.17" ];
    $packet = "";
    $packet .= construct_ether(\%ether);
    $packet .= construct_ip4(\%ip4,
	construct_ospf(\%ospf,
	construct_hello(\%hello)));

    $n = syswrite($tun, $packet);
    defined($n) or die "syswrite failed: $!";
    print "Wrote $n bytes\n";
}

print "Terminating\n"
