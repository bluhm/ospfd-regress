# Copyright (c) 2014 Alexander Bluhm <bluhm@openbsd.org>
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

# Encapsulate tun interface handling into separate module.

use strict;
use warnings;

package Tun;
use parent 'Exporter';
our @EXPORT_OK = qw(opentun);

use Carp;
use Fcntl qw(F_SETFD FD_CLOEXEC);
use POSIX qw(_exit);
use PassFd 'recvfd';
use Socket;

sub opentun {
    my ($tunnumber) = @_;

    socketpair(my $parent, my $child, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
	or carp "Socketpair failed: $!";
    $child->fcntl(F_SETFD, 0)
	or carp "Fcntl setfd failed: $!";

    defined(my $pid = fork())
	or carp "Fork failed: $!";
    unless ($pid) {
	# child process
	close($parent)
	    or do { warn "Close parent socket failed: $!"; _exit(3); };
	my @cmd = ('sudo', '-C', $child->fileno()+1, './opentun',
	    $child->fileno(), $tunnumber);
	exec(@cmd);
	warn "exec @cmd failed: $!";
	_exit(3);
    }
    # parent process
    close($child)
	or carp "Close child socket failed: $!";
    my $tun = recvfd($parent)
	or carp "Recvfd failed: $!";
    wait()
	or carp "Wait failed: $!";
    $? == 0
	or carp "Child process failed: $?";

    return $tun;
}

1;
