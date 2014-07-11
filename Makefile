# The following ports must be installed for the regression tests:
# p5-AnyEvent		provide framework for multiple event loops
#
# Check wether all required perl packages are installed.  If some
# are missing print a warning and skip the tests, but do not fail.

PERL_REQUIRE != perl -Mstrict -Mwarnings -e ' \
    eval { require AnyEvent } or print $@; \
'
.if ! empty (PERL_REQUIRE)
regress:
	@echo "${PERL_REQUIRE}"
	@echo install these perl packages for additional tests
.endif

# Automatically generate regress targets from test cases in directory.

ARGS !=			cd ${.CURDIR} && ls args-*.pl
TARGETS ?=		${ARGS}
REGRESS_TARGETS =	${TARGETS:S/^/run-regress-/}
CLEANFILES +=		*.log ospfd.conf ktrace.out stamp-* opentun
PERLHEADER !=		perl -MConfig -e 'print "$$Config{archlib}/CORE"'
CLEANFILES +=		PassFd.c PassFd.o PassFd.so
TUNDEV ?=		6
TUNIP ?=		10.188.6.17
RTRID ?=		10.188.0.17
CFLAGS =		-Wall

# Set variables so that make runs with and without obj directory.
# Only do that if necessary to keep visible output short.

.if ${.CURDIR} == ${.OBJDIR}
PERLINC =
PERLPATH =
.else
PERLINC =	-I${.CURDIR}
PERLPATH =	${.CURDIR}/
.endif

# The arg tests take a perl hash with arguments controlling the
# test parameters.

.for a in ${ARGS}
run-regress-$a: $a opentun PassFd.so
	@echo '\n======== $@ ========'
	@-${SUDO} ifconfig tun${TUNDEV} ${TUNIP} netmask 255.255.255.0 link0
	time TUNDEV=${TUNDEV} TUNIP=${TUNIP} RTRID=${RTRID} SUDO=${SUDO} KTRACE=${KTRACE} OSPFD=${OSPFD} perl ${PERLINC} ${PERLPATH}ospfd.pl ${PERLPATH}$a
.endfor

# make perl syntax check for all args files

.PHONY: syntax

syntax: stamp-syntax

stamp-syntax: ${ARGS} passfd
.for a in ${ARGS}
	@perl ${PERLINC} -c ${PERLPATH}$a
.endfor
	@date >$@

# build and test file descriptor passing perl xs module

.PHONY: passfd

passfd: stamp-passfd

stamp-passfd: PassFd.so
	perl ${PERLINC} ${PERLPATH}testfd.pl
	@date >$@

.SUFFIXES: .xs .so

.xs.so:
	xsubpp -prototypes $> >${@:S/.so$/.c/}
	gcc -shared -Wall -I${PERLHEADER} -o $@ ${@:S/.so$/.c/}
	perl ${PERLINC} -M${@:R} -e ''

.include <bsd.regress.mk>
