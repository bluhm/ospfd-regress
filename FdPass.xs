#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <sys/socket.h>

MODULE = FdPass	PACKAGE = FdPass

PerlIO *
recvfd(PerlIO *so)
    PREINIT:
	PerlIO		*fh;
	int		 s, fd;
	struct msghdr	 msg;
	struct cmsghdr	*cmsg;
	union {
		struct cmsghdr	 hdr;
		unsigned char	 buf[CMSG_SPACE(sizeof(int))];
	} cmsgbuf;
    CODE:
	s = PerlIO_fileno(so);

	memset(&msg, 0, sizeof(msg));
	msg.msg_control = &cmsgbuf.buf;
	msg.msg_controllen = sizeof(cmsgbuf.buf);

	if (recvmsg(s, &msg, 0) == -1)
		XSRETURN_UNDEF;
	if ((msg.msg_flags & MSG_TRUNC) || (msg.msg_flags & MSG_CTRUNC)) {
		errno = EMSGSIZE;
		XSRETURN_UNDEF;
	}
	for (cmsg = CMSG_FIRSTHDR(&msg); cmsg != NULL;
	    cmsg = CMSG_NXTHDR(&msg, cmsg)) {
		if (cmsg->cmsg_len == CMSG_LEN(sizeof(int)) &&
		    cmsg->cmsg_level == SOL_SOCKET &&
		    cmsg->cmsg_type == SCM_RIGHTS) {
			fd = *(int *)CMSG_DATA(cmsg);
			if ((fh = PerlIO_fdopen(fd, "r+")) == NULL)
				XSRETURN_UNDEF;
			RETVAL = fh;
			break;
		}
	}
    OUTPUT:
	RETVAL
