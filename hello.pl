#!/usr/bin/perl

use strict;
use warnings;
use Fcntl;
use Data::Dumper;
use YAML;

my $tun_device = 6;
my $mac_address = "1:2:3:4:5:6";
my $ospf_address = "10.188.6.18";
my $router_id = "10.188.6.18";

sub ip_checksum {
    my ($msg) = @_;
    my $chk = 0;
    foreach my $short (unpack("n*", $msg."\0")) {
	$chk += $short;
    }
    $chk = ($chk >> 16) + ($chk & 0xffff);
    return(~(($chk >> 16) + $chk) & 0xffff);
}

sub consume_ether {
    my $packet = shift;

    length($$packet) >= 14 or die "ether packet too short: ". length($$packet);
    my $ether = substr($$packet, 0, 14, "");
    my %fields;
    @fields{qw(dst src type)} = unpack("a6 a6 n", $ether);
    foreach my $addr (qw(src dst)) {
	$fields{"${addr}_str"} = sprintf("%02x:%02x:%02x:%02x:%02x:%02x",
	    unpack("C6", $fields{$addr}));
    }

    return %fields;
}

sub construct_ether {
    my $fields = shift;

    foreach my $addr (qw(src dst)) {
	$$fields{$addr} = 
	    pack("C6", map { hex $_ } split(/:/, $$fields{"${addr}_str"}));
    }
    my $packet = pack("a6 a6 n", @$fields{qw(dst src type)});

    return $packet;
}

sub consume_ip4 {
    my $packet = shift;

    length($$packet) >= 20 or die "ip packet too short: ". length($$packet);
    my $ip4 = substr($$packet, 0, 20, "");
    my %fields;
    @fields{qw(hlv tos len id off ttl p sum src dst)} =
	unpack("C C n n n C C n a4 a4", $ip4);
    $fields{hlen} = ($fields{hlv} & 0x0f) << 2;
    $fields{v} = ($fields{hlv} >> 4) & 0x0f;

    $fields{v} == 4 or die "ip version is not 4: $fields{v}";
    $fields{hlen} >= 20 or die "ip header length too small: $fields{hlen}";
    if ($fields{hlen} > 20) {
	$fields{options} = substr($$packet, 0, 20 - $fields{hlen}, "");
    }
    foreach my $addr (qw(src dst)) {
	$fields{"${addr}_str"} = join(".", unpack("C4", $fields{$addr}));
    }

    return %fields;
}

sub construct_ip4 {
    my $fields = shift;

    $$fields{hlv} //= 0x45;
    if ($$fields{hlen}) {
	$$fields{hlen} & 3 and die "bad ip4 header length: $$fields{hlen}";
	$$fields{hlen} < 20
	    and die "ip4 header length too small: $$fields{hlen}";
	($$fields{hlen} >> 2) > 0x0f
	    and die "ip4 header length too big: $$fields{hlen}";
	$$fields{hlen} != length($$fields{options} // "") + 20
	    and die "ip4 header length does not match options: $$fields{hlen}";
	$$fields{hlv} &= 0xf0;
	$$fields{hlv} |= ($$fields{hlen} >> 2) & 0x0f;
    }
    if ($$fields{v}) {
	$$fields{hlv} &= 0x0f;
	$$fields{hlv} |= ($$fields{v} << 4) & 0xf0;
    }
    foreach my $addr (qw(src dst)) {
	$$fields{$addr} = pack("C4", split(/\./, $$fields{"${addr}_str"}));
    }
    my $packet = pack("C C n n n C C xx a4 a4",
	@$fields{qw(hlv tos len id off ttl p src dst)});
    $$fields{sum} = ip_checksum($packet);
    substr($packet, 10, 2, pack("n", $$fields{sum}));

    if ($$fields{options}) {
	$packet .= pack("a*", $$fields{options});
	$$fields{options} = substr($$packet, 0, 20 - $$fields{hlen}, "");
    }

    return $packet;
}

sub consume_ospf {
    my $packet = shift;

    length($$packet) >= 24 or die "ospf packet too short: ". length($$packet);
    my $ospf = substr($$packet, 0, 24, "");
    my %fields;
    @fields{qw(version type packet_length router_id area_id checksum autype
	authentication)} =
	unpack("C C n a4 a4 n n a8", $ospf);
    $fields{version} == 2 or die "ospf version is not 2: $fields{v}";
    foreach my $addr (qw(router_id area_id)) {
	$fields{"${addr}_str"} = join(".", unpack("C4", $fields{$addr}));
    }

    return %fields;
}

sub construct_ospf {
    my $fields = shift;

    foreach my $addr (qw(router_id area_id)) {
	if ($$fields{"${addr}_str"}) {
	    $$fields{$addr} = join(".", unpack("C4", $$fields{"${addr}_str"}));
	}
    }
    my $packet = pack("C C n a4 a4 xx n",
	@$fields{qw(version type packet_length router_id area_id autype)});
    $$fields{checksum} = ip_checksum($packet);
    substr($packet, 12, 2, pack("n", $$fields{checksum}));
    $packet .= pack("a8", $$fields{authentication});

    return $packet;
}

sub consume_hello {
    my $packet = shift;

    length($$packet) >= 20 or die "hello packet too short: ". length($$packet);
    my $hello = substr($$packet, 0, 20, "");
    my %fields;
    @fields{qw(network_mask hellointerval options rtr_pri
	routerdeadinterval designated_router backup_designated_router)} =
	unpack("a4 n C C N A4 A4", $hello);
    foreach my $addr (qw(network_mask designated_router
	backup_designated_router)) {
	$fields{"${addr}_str"} = join(".", unpack("C4", $fields{$addr}));
    }
    length($$packet) % 4 and die "bad neighbor length: ". length($$packet);
    my $n = length($$packet) / 4;
    $fields{neighbors} = [unpack("a4" x $n, $$packet)];
    $$packet = "";
    foreach my $addr (@{$fields{neighbors}}) {
	push @{$fields{neighbors_str}}, join(".", unpack("C4", $addr));
    }

    return %fields;
}

sub construct_hello {
    my $fields = shift;

    foreach my $addr (qw(network_mask designated_router
	backup_designated_router)) {
	if ($$fields{"${addr}_str"}) {
	    $$fields{$addr} = pack("C4", split(/\./, $$fields{"${addr}_str"}));
	}
    }
    my $packet = pack("a4 n C C N A4 A4",
	@$fields{qw(network_mask hellointerval options rtr_pri
	    routerdeadinterval designated_router backup_designated_router)});

    foreach my $str (@{$$fields{neighbors_str}}) {
	push @{$$fields{neighbors}}, pack("C4", split(/\./, $str));
    }
    my $n = @{$$fields{neighbors}};
    $packet .= pack("a4" x $n, @{$$fields{neighbors}});

    return $packet;
}

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
    $hello{router_id} = $router_id;
    $packet = "";
    $packet .= construct_ether(\%ether);
    $packet .= construct_ip4(\%ip4);
    $packet .= construct_ospf(\%ospf);
    $packet .= construct_hello(\%hello);

    $n = syswrite($tun, $packet);
    defined($n) or die "syswrite failed: $!";
    print "Wrote $n bytes\n";
}

print "Terminating\n"
