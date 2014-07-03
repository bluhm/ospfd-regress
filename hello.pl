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

my $tun_device = "/dev/tun6";
my $mac_address = "1:2:3:4:5:6";
my $ospf_address = "10.188.6.18";
my $router_id = "10.188.6.18";

my $cv = AnyEvent->condvar;

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
    on_read => sub {
	my %ether = consume_ether(\$handle->{rbuf});
	unless ($ether{type} == 0x0800) {
	    warn "ether type is not ip";
	    return;
	}
	my %ip = consume_ip(\$handle->{rbuf});
	unless ($ip{p} == 89) {
	    warn "ip proto is not ospf";
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
	$ip{src_str} = $ospf_address;
	$ospf{router_id_str} = $router_id;
	$hello{backup_designated_router_str} = $router_id;
	$hello{neighbors_str} = [ "10.188.6.17" ];
	$handle->push_write(
	    construct_ether(\%ether,
	    construct_ip(\%ip,
	    construct_ospf(\%ospf,
	    construct_hello(\%hello))))
	);
    },
);

$cv->recv;

print "Terminating\n"
