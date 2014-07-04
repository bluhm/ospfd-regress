#!/usr/bin/perl

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

use Ospfd;
use Client;

sub usage {
    die "usage: ospf.pl [test-args.pl]\n";
}

my $test;
our %tst_args;
if (@ARGV and -f $ARGV[-1]) {
    $test = pop;
    do $test
	or die "Do test file $test failed: ", $@ || $!;
}
@ARGV == 0 or usage();

my $o = Ospfd->new(
    %{$tst_args{ospfd}},
);

$o->run;
$o->up;
if ($tst_args{client}) {
    my $c = Client->new(
	%{$tst_args{client}},
    );
    $c->run;
    $c->down;
}
$o->kill_child;
$o->down;
