# Automatically generate regress targets from test cases in directory.

ARGS !=			cd ${.CURDIR} && ls args-*.pl
TARGETS ?=		${ARGS}
REGRESS_TARGETS =	${TARGETS:S/^/run-regress-/}
CLEANFILES +=		*.log ospfd.conf ktrace.out stamp-*
TUNDEV ?=		tun99
TUNIP ?=		10.11.12.1

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
	@-${SUDO} sh -c 'cd /dev && sh MAKEDEV tun99'
	@-${SUDO} ifconfig ${TUNDEV} ${TUNIP} netmask 255.255.255.0 link0
	time TUNDEV=${TUNDEV} TUNIP=${TUNIP} SUDO=${SUDO} KTRACE=${KTRACE} OSPFD=${OSPFDD} perl ${PERLINC} ${PERLPATH}ospfd.pl ${PERLPATH}$a
	@-${SUDO} ifconfig ${TUNDEV} destroy
	@-${SUDO} rm -f /dev/${TUNDEV}
.endfor

# make perl syntax check for all args files

.PHONY: syntax

syntax: stamp-syntax

stamp-syntax: ${ARGS}
.for a in ${ARGS}
	@perl -c ${PERLPATH}$a
.endfor
	@date >$@

.include <bsd.regress.mk>
