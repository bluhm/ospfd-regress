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

# TODO interface.pl must be a parameter
sub perl_client {
	my @cmd=("perl", "interface.pl");
	exec(@cmd) or die "exec @cmd failed: $!";
}

sub new {
	my ($class, $client, %args) = @_;
	$args{logfile} ||= "client.log";
	$args{up} = "Starting test client";
	$args{down} = "Terminating";
	$args{func} = \&perl_client;
	my $self = Proc::new($class, %args);
	return $self;
}

# TODO delete it if we don't need it
sub child {
	my $self = shift;
}

1;
