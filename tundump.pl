#!/usr/bin/perl

use strict;
use warnings;
use Socket;
use POSIX;
use Fcntl qw(F_SETFD FD_CLOEXEC);
use FdPass 'recvfd';

socketpair(my $parent, my $child, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
    or die "socketpair failed: $!";
$child->fcntl(F_SETFD, 0)
    or die "fcntl setfd failed: $!";

defined(my $pid = fork())
    or die "fork failed: $!";
unless ($pid) {
    # child process
    close($parent);
    my @cmd = ('sudo', '-C', $child->fileno()+1, './opentun',
	$child->fileno(), 6);
    exec(@cmd);
    warn "exec @cmd failed: $!";
    POSIX::_exit(1);
}
# parent process
close($child);
my $tun = recvfd($parent)
    or die "recvfd failed: $!";
wait();

for (;;) {
    my $n = sysread($tun, my $buf, 70000);
    defined($n) or die "sysread failed: $!";
    $n or last;
    print "Read $n bytes\n";
    print unpack("H*", $buf), "\n";
}

print "Terminating\n"
