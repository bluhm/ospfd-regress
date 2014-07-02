# Automatically generate regress targets from test cases in directory.

ARGS !=			cd ${.CURDIR} && ls args-*.pl
TARGETS ?=		${ARGS}
REGRESS_TARGETS =	${TARGETS:S/^/run-regress-/}
CLEANFILES +=		*.log ospfd.conf ktrace.out stamp-*
TUNDEV ?=		tun5
TUNIP ?=		10.188.6.17

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
run-regress-$a: $a
	@-${SUDO} ifconfig ${TUNDEV} ${TUNIP} netmask 255.255.255.0 link0
	time TUNDEV=${TUNDEV} TUNIP=${TUNIP} SUDO=${SUDO} KTRACE=${KTRACE} OSPFD=${OSPFD} perl ${PERLINC} ${PERLPATH}ospfd.pl ${PERLPATH}$a
	@-${SUDO} ifconfig ${TUNDEV} destroy
.endfor

# make perl syntax check for all args files

.PHONY: syntax

syntax: stamp-syntax

stamp-syntax: ${ARGS}
.for a in ${ARGS}
	@perl -c ${PERLPATH}$a
.endfor
	@date >$@

.SUFFIXES: .xs .so

.xs.so:
	xsubpp -prototypes $> >${@:S/.so$/.c/}
	gcc -shared -Wall -I/usr/libdata/perl5/amd64-openbsd/5.18.2/CORE -o $@ ${@:S/.so$/.c/}
	perl -M${@:R} -e ''

.include <bsd.regress.mk>
